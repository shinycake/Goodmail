import MailCore
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// The files added to a message: a glass capsule each, with Remove in its menu.
final class ComposeAttachmentsView: UIStackView {
    var onRemove: ((DraftAttachment.ID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        alignment = .leading
        spacing = 8
        isHidden = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Programmatic UI only") }

    func show(_ attachments: [DraftAttachment]) {
        for view in arrangedSubviews { view.removeFromSuperview() }
        for attachment in attachments {
            var configuration = UIButton.Configuration.glass()
            configuration.cornerStyle = .capsule
            configuration.image = UIImage(systemName: AttachmentListView.symbol(for: attachment.mimeType))
            configuration.imagePadding = 8
            configuration.title = attachment.filename
            configuration.subtitle = AttachmentListView.sizeText(attachment.size)
            configuration.titleLineBreakMode = .byTruncatingMiddle
            configuration.baseForegroundColor = .label
            let button = UIButton(configuration: configuration)
            button.menu = UIMenu(children: [
                UIAction(
                    title: String(localized: "Remove", bundle: .module, comment: "Takes a file off the message"),
                    image: UIImage(systemName: "xmark"), attributes: .destructive
                ) { [weak self] _ in self?.onRemove?(attachment.id) }
            ])
            button.showsMenuAsPrimaryAction = true
            button.accessibilityLabel =
                "\(attachment.filename), \(AttachmentListView.sizeText(attachment.size))"
            addArrangedSubview(button)
        }
        isHidden = attachments.isEmpty
    }
}

extension ComposeViewController {
    /// The paperclip: a menu of where to take files from.
    func attachItem() -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(localized: "Attach", bundle: .module, comment: "Adds files to the message"),
            image: UIImage(systemName: "paperclip"),
            menu: UIMenu(children: [
                UIAction(
                    title: String(localized: "Photo Library", bundle: .module, comment: "Attach from Photos"),
                    image: UIImage(systemName: "photo.on.rectangle")
                ) { [weak self] _ in self?.choosePhotos() },
                UIAction(
                    title: String(localized: "Choose File", bundle: .module, comment: "Attach from Files"),
                    image: UIImage(systemName: "folder")
                ) { [weak self] _ in self?.chooseFiles() },
            ]))
    }

    private func choosePhotos() {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func chooseFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    static func attachment(data: Data, filename: String, type: UTType?) -> DraftAttachment {
        DraftAttachment(
            filename: filename, mimeType: type?.preferredMIMEType ?? "application/octet-stream", data: data)
    }

    func tooLarge() {
        let alert = UIAlertController(
            title: String(localized: "File Too Large", bundle: .module, comment: "Alert title"),
            message: String(
                localized: "Gmail sends up to 25 MB of attachments in one message.", bundle: .module,
                comment: "Alert explaining the attachment size limit"),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: String(localized: "OK", bundle: .module, comment: "Dismiss"), style: .default))
        present(alert, animated: true)
    }
}

extension ComposeViewController: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        // One at a time, so they land in the order they were picked.
        Task {
            for result in results {
                if let attachment = await Self.attachment(from: result.itemProvider) { add(attachment) }
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

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // In order, as with photos.
        Task {
            for url in urls {
                guard let data = await Self.contents(of: url) else { continue }
                add(
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
