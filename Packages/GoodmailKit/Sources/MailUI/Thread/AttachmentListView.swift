import MailCore
import UIKit
import UniformTypeIdentifiers

/// A message's files, one glass capsule each: an icon for the kind of file, its name and its size.
final class AttachmentListView: UIStackView {
    var onOpen: ((Attachment) -> Void)?
    private var attachments: [Attachment] = []
    private var buttons: [String: UIButton] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        alignment = .leading
        spacing = 8
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// The attachments a reader opens: files, and inline parts the body doesn't place itself.
    static func listed(in message: Message) -> [Attachment] {
        message.attachments.filter { !$0.isInline || $0.contentID == nil }
    }

    func show(_ attachments: [Attachment]) {
        guard attachments != self.attachments else { return }
        self.attachments = attachments
        for view in arrangedSubviews { view.removeFromSuperview() }
        buttons = [:]
        for attachment in attachments {
            let button = UIButton(configuration: Self.configuration(for: attachment))
            button.addAction(UIAction { [weak self] _ in self?.onOpen?(attachment) }, for: .primaryActionTriggered)
            button.accessibilityLabel = "\(attachment.filename), \(Self.sizeText(attachment.size))"
            buttons[attachment.id] = button
            addArrangedSubview(button)
        }
        isHidden = attachments.isEmpty
    }

    /// Shows a spinner on the attachment's capsule while its data downloads.
    func setLoading(_ loading: Bool, for attachment: Attachment) {
        buttons[attachment.id]?.configuration?.showsActivityIndicator = loading
    }

    private static func configuration(for attachment: Attachment) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.glass()
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: symbol(for: attachment.mimeType))
        configuration.imagePadding = 8
        configuration.title = attachment.filename
        configuration.subtitle = sizeText(attachment.size)
        configuration.titleLineBreakMode = .byTruncatingMiddle
        configuration.baseForegroundColor = .label
        return configuration
    }

    static func symbol(for mimeType: String) -> String {
        guard let type = UTType(mimeType: mimeType) else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if type.conforms(to: .calendarEvent) { return "calendar" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    static func sizeText(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}
