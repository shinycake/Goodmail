import MailCore
import UIKit

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
                    title: String(
                        localized: "Remove", table: "Compose", bundle: .module, comment: "Takes a file off the message"),
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
            title: String(localized: "Attach", table: "Compose", bundle: .module, comment: "Adds files to the message"),
            image: UIImage(systemName: "paperclip"), menu: UIMenu(children: picker.actions()))
    }

    func tooLarge() {
        let alert = UIAlertController(
            title: String(localized: "File Too Large", table: "Compose", bundle: .module, comment: "Alert title"),
            message: String(
                localized: "Gmail sends up to 25 MB of attachments in one message.", table: "Compose", bundle: .module,
                comment: "Alert explaining the attachment size limit"),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(localized: "OK", table: "Compose", bundle: .module, comment: "Dismiss"), style: .default))
        present(alert, animated: true)
    }
}

extension AttachmentSource {
    var title: String {
        switch self {
        case .photoLibrary:
            String(localized: "Photo Library", table: "Compose", bundle: .module, comment: "Attach from Photos")
        case .file:
            String(localized: "Choose File", table: "Compose", bundle: .module, comment: "Attach from Files")
        case .camera:
            String(
                localized: "Take Photo", table: "Compose", bundle: .module, comment: "Attach a picture from the camera")
        case .scan:
            String(
                localized: "Scan Document", table: "Compose", bundle: .module,
                comment: "Attach a scanned document as a PDF")
        }
    }

    var symbol: String {
        switch self {
        case .photoLibrary: "photo.on.rectangle"
        case .file: "folder"
        case .camera: "camera"
        case .scan: "doc.viewfinder"
        }
    }
}
