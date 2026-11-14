import MailCore
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// Takes files for a message from the places `AttachmentSource` names: picked photos and files, a photo from the
/// camera, or a scan as one PDF. Each lands through `add`, in the order it was chosen. The composer and the chat's
/// quick reply each own one.
final class AttachmentPicker: NSObject {
    /// The screen the pickers and any alert present from.
    weak var presenter: UIViewController?
    private let add: (DraftAttachment) -> Void
    /// Photos and scans waiting to be turned into attachments, in the order they were taken.
    private let captures = AsyncStream.makeStream(of: CapturedAttachment.Preparation.self)
    /// Prepares `captures` one at a time. `finish()` stops the one in hand and every one waiting.
    private var preparing: Task<Void, Never>?

    init(add: @escaping (DraftAttachment) -> Void) {
        self.add = add
        super.init()
        preparing = Task { [weak self, captures = captures.stream] in
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

    /// Stops preparing captures: the message they were for is gone.
    func finish() {
        captures.continuation.finish()
        preparing?.cancel()
    }

    /// One action per source this device has, in menu order.
    func actions() -> [UIAction] {
        AttachmentSource.available(on: .current).map { source in
            UIAction(title: source.title, image: UIImage(systemName: source.symbol)) { [weak self] _ in
                self?.choose(source)
            }
        }
    }

    func choose(_ source: AttachmentSource) {
        switch source {
        case .photoLibrary:
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 0
            configuration.preferredAssetRepresentationMode = .compatible
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            presenter?.present(picker, animated: true)
        case .file:
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.allowsMultipleSelection = true
            picker.delegate = self
            presenter?.present(picker, animated: true)
        case .camera:
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = self
            presenter?.present(picker, animated: true)
        case .scan:
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = self
            presenter?.present(scanner, animated: true)
        }
    }

    /// Queues a capture to be prepared off the main actor and attached after the ones taken before it.
    private func attach(_ make: @escaping CapturedAttachment.Preparation) {
        captures.continuation.yield(make)
    }

    static func attachment(data: Data, filename: String, type: UTType?) -> DraftAttachment {
        DraftAttachment(
            filename: filename, mimeType: type?.preferredMIMEType ?? "application/octet-stream", data: data)
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
        presenter?.present(alert, animated: true)
    }
}

extension AttachmentPicker: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        // One at a time, so they land in the order they were picked.
        Task { [weak self] in
            for result in results {
                if let attachment = await Self.attachment(from: result.itemProvider) { self?.add(attachment) }
            }
        }
    }

    private static func attachment(from provider: NSItemProvider) async -> DraftAttachment? {
        let types = provider.registeredContentTypes
        guard let type = types.first(where: { $0.conforms(to: .image) || $0.conforms(to: .movie) }) ?? types.first
        else { return nil }
        let name = (provider.suggestedName ?? "Photo") + (type.preferredFilenameExtension.map { ".\($0)" } ?? "")
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
        }
        return data.map { attachment(data: $0, filename: name, type: type) }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // In order, as with photos.
        Task { [weak self] in
            for url in urls {
                guard let data = await Self.contents(of: url) else { continue }
                self?.add(
                    Self.attachment(
                        data: data, filename: url.lastPathComponent, type: UTType(filenameExtension: url.pathExtension)
                    ))
            }
        }
    }

    /// Reads a picked file off the main actor: it can be tens of megabytes.
    @concurrent private static func contents(of url: URL) async -> Data? {
        try? Data(contentsOf: url)
    }
}

extension AttachmentPicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = info[.originalImage] as? UIImage
        let date = Date()
        picker.dismiss(animated: true) { [self] in
            guard let image else { return couldNotPrepare() }
            attach { try await CapturedAttachment.photo(image, at: date) }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension AttachmentPicker: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
    ) {
        let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
        let date = Date()
        controller.dismiss(animated: true) { [self] in
            attach { try await CapturedAttachment.scan(pages: pages, at: date) }
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true) { [self] in couldNotPrepare() }
    }
}
