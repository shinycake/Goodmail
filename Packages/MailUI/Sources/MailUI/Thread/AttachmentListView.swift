import MailCore
import UIKit
import UniformTypeIdentifiers

/// A message's files, one glass capsule each: an icon for the kind of file, its name and its size.
final class AttachmentListView: UIStackView {
    var onOpen: ((Attachment) -> Void)?
    /// Save to Downloads, on a desktop window's context menu.
    var onSave: ((Attachment) -> Void)?
    private var attachments: [Attachment] = []
    private var buttons: [String: ReaderAttachmentChip] = [:]

    /// The chip the reader selected on a desktop window, which has the keyboard.
    var selectedChip: ReaderAttachmentChip? { buttons.values.first(where: \.isFirstResponder) }

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
            let button = ReaderAttachmentChip(attachment: attachment)
            button.onOpen = { [weak self] in self?.onOpen?(attachment) }
            button.onSave = { [weak self] in self?.onSave?(attachment) }
            button.accessibilityLabel = "\(attachment.filename), \(Self.sizeText(attachment.size))"
            button.accessibilityUserInputLabels = [attachment.filename]
            buttons[attachment.id] = button
            addArrangedSubview(button)
        }
        isHidden = attachments.isEmpty
    }

    /// Shows a spinner on the attachment's capsule while its data downloads.
    func setLoading(_ loading: Bool, for attachment: Attachment) {
        buttons[attachment.id]?.showsDownloading(loading)
    }

    static func configuration(for attachment: Attachment) -> UIButton.Configuration {
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

extension UIButton {
    /// Spins on an attachment's button while its data downloads, and tells VoiceOver it is downloading, which the
    /// spinner alone doesn't.
    func showsDownloading(_ downloading: Bool) {
        configuration?.showsActivityIndicator = downloading
        accessibilityValue =
            downloading
            ? String(
                localized: "Downloading", table: "Thread", bundle: .module,
                comment: "VoiceOver: an attachment's data is on its way")
            : nil
    }
}
