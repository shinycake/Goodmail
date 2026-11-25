import MailCore
import ObjectiveC
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// Takes files for a message from the places `AttachmentSource` names: picked photos and files, a photo from the
/// camera, or a scan as one PDF. Every one goes through one queue, prepared one at a time off the main actor, and
/// lands through `add` in the order it was chosen, until the place that owns the picker finishes it. The composer and
/// the chat's quick reply each own one.
final class AttachmentPicker: NSObject {
    /// The screen the pickers and any alert present from.
    weak var presenter: UIViewController?
    private let add: (DraftAttachment) -> Void
    /// Whether files are still taken. Only `queue` and `finish` change it.
    private var phase = Phase.open

    private enum Phase {
        /// Taking files, none chosen yet.
        case open
        /// Taking files: `queue` holds the ones chosen and not yet prepared, which `preparing` works through.
        case accepting(queue: AsyncStream<Chosen>.Continuation, preparing: Task<Void, Never>)
        /// The place is gone: nothing more is picked, prepared or added.
        case finished
    }

    /// Something chosen to attach, before it is read or encoded.
    private enum Chosen {
        case photo(NSItemProvider)
        case file(URL)
        case capture(CapturedAttachment.Preparation)
    }

    init(add: @escaping (DraftAttachment) -> Void) {
        self.add = add
        super.init()
    }

    isolated deinit {
        finish()
    }

    /// Stops taking files, the one being prepared and every one waiting included: the message they were for is gone.
    /// Whatever was still being read is dropped, not attached to whatever the place writes next.
    func finish() {
        if case .accepting(let queue, let preparing) = phase {
            queue.finish()
            preparing.cancel()
        }
        phase = .finished
    }

    /// Prepares what is chosen, one at a time, in order, until the picker finishes. The phase alone decides whether
    /// what was prepared still lands: a capture that fails says so and the queue goes on.
    private func startPreparing() -> Phase {
        let (chosen, queue) = AsyncStream.makeStream(of: Chosen.self)
        let preparing = Task { [weak self] in
            for await next in chosen {
                let prepared: Prepared
                do {
                    prepared = .ready(try await Self.prepare(next))
                } catch {
                    prepared = .failed
                }
                guard let self, case .accepting = phase else { return }
                switch prepared {
                case .ready(let attachment?): add(attachment)
                case .ready(nil): break
                case .failed: couldNotPrepare()
                }
            }
        }
        return .accepting(queue: queue, preparing: preparing)
    }

    /// What preparing one choice came to.
    private enum Prepared {
        /// Its attachment, or `nil` when there was nothing to read.
        case ready(DraftAttachment?)
        case failed
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
        if case .finished = phase { return }
        switch source {
        case .photoLibrary:
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 0
            configuration.preferredAssetRepresentationMode = .compatible
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker)
        case .file:
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.allowsMultipleSelection = true
            picker.delegate = self
            present(picker)
        case .camera:
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = self
            present(picker)
        case .scan:
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = self
            present(scanner)
        }
    }

    /// Presents `sheet`, which keeps this picker, its delegate, for as long as the sheet lives. The place can let the
    /// picker go while the sheet is up, as a chat reply sent or a reader left does, and a sheet whose delegate is gone
    /// can't be dismissed: its delegate methods dismiss it before anything else, finished or not.
    func present(_ sheet: UIViewController) {
        // Safe: the key is a byte allocated once and never freed, used only for its address; the runtime retains the
        // picker for the sheet and releases it with the sheet.
        unsafe objc_setAssociatedObject(sheet, Self.sheetKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        presenter?.present(sheet, animated: true)
    }

    /// The key a sheet keeps its picker under.
    private static let sheetKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    /// Queues a capture to be prepared off the main actor and attached after the ones chosen before it.
    func attach(_ make: @escaping CapturedAttachment.Preparation) {
        queue(.capture(make))
    }

    /// Queues what was chosen, to be prepared and attached after the ones chosen before it.
    private func queue(_ chosen: Chosen) {
        switch phase {
        case .finished: return
        case .open: phase = startPreparing()
        case .accepting: break
        }
        guard case .accepting(let queue, _) = phase else { return }
        queue.yield(chosen)
    }

    /// Reads or encodes what was chosen into its attachment; `nil` when there was nothing to read.
    private static func prepare(_ chosen: Chosen) async throws -> DraftAttachment? {
        switch chosen {
        case .photo(let provider):
            return await attachment(from: provider)
        case .file(let url):
            return await contents(of: url).map {
                attachment(
                    data: $0, filename: url.lastPathComponent, type: UTType(filenameExtension: url.pathExtension))
            }
        case .capture(let make):
            return try await make()
        }
    }

    static func attachment(data: Data, filename: String, type: UTType?) -> DraftAttachment {
        DraftAttachment(
            filename: filename, mimeType: type?.preferredMIMEType ?? "application/octet-stream", data: data)
    }

    private func couldNotPrepare() {
        if case .finished = phase { return }
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
        for result in results { queue(.photo(result.itemProvider)) }
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
        for url in urls { queue(.file(url)) }
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

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
        controller.dismiss(animated: true) { [self] in couldNotPrepare() }
    }
}
