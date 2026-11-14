import MailCore
import UIKit
import VisionKit

/// Attaching what the camera sees: a photo, or a scanned document as one PDF.
extension ComposeViewController {
    func takePhoto() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    func scanDocument() {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        present(scanner, animated: true)
    }

    /// Queues a capture to be prepared off the main actor and attached after the ones taken before it.
    private func attach(_ make: @escaping CapturedAttachment.Preparation) {
        captures.continuation.yield(make)
    }

    /// The one worker that prepares captures in order. It holds the controller weakly, so it never keeps a closed
    /// message alive.
    func preparingCaptures() -> Task<Void, Never> {
        Task { [weak self, captures = captures.stream] in
            for await make in captures {
                do {
                    let attachment = try await make()
                    try Task.checkCancellation()
                    self?.add(attachment)
                } catch is CancellationError {
                    return  // The message closed; nothing is left to attach to.
                } catch {
                    self?.couldNotPrepare()
                }
            }
        }
    }

    private func couldNotPrepare() {
        let alert = UIAlertController(
            title: String(localized: "Couldn't Attach", table: "Compose", bundle: .module, comment: "Alert title"),
            message: String(
                localized: "Goodmail couldn't prepare that for the message.", table: "Compose", bundle: .module,
                comment: "Alert when a photo or scan can't be turned into a file"),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(localized: "OK", table: "Compose", bundle: .module, comment: "Dismiss"), style: .default))
        present(alert, animated: true)
    }
}

extension ComposeViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(
        _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = info[.originalImage] as? UIImage
        let date = Date()
        picker.dismiss(animated: true) { [self] in
            guard let image else { return couldNotPrepare() }
            attach { try await CapturedAttachment.photo(image, at: date) }
        }
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension ComposeViewController: VNDocumentCameraViewControllerDelegate {
    public func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
    ) {
        let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
        let date = Date()
        controller.dismiss(animated: true) { [self] in
            attach { try await CapturedAttachment.scan(pages: pages, at: date) }
        }
    }

    public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    public func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFailWithError error: Error
    ) {
        controller.dismiss(animated: true) { [self] in couldNotPrepare() }
    }
}
