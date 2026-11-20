import MailCore
import UIKit

/// An open message: a rounded card with its header, then the body in its own web view. While the app is dark, a sun
/// in the header switches the card to light and back (`MessageAppearance`).
final class MessageCardView: UIView {
    var onToggle: (() -> Void)?
    var onAllowRemoteContent: (() -> Void)?
    /// Keeps a rule the reader chose for the sender or their domain, so those remote images always load.
    var onTrust: ((ImageTrustRule) -> Void)?
    var onOpenAttachment: ((Attachment) -> Void)? {
        didSet { attachments.onOpen = onOpenAttachment }
    }
    var onSaveAttachment: ((Attachment) -> Void)? {
        didSet { attachments.onSave = onSaveAttachment }
    }
    var openURL: ((URL) -> Void)? {
        didSet { body.openURL = openURL }
    }
    /// The link the pointer is over in the body, or `nil` once it leaves (a desktop window).
    var onHoverLink: ((URL?) -> Void)? {
        didSet { body.onHoverLink = onHoverLink }
    }
    /// Called each time the body takes its height, which can come seconds after the card shows.
    var onBodyLayout: (() -> Void)?

    /// The rounded card itself, which carries the appearance override. The view around it keeps the app's, so it
    /// knows when the app is dark.
    private let surface = UIView()
    let appearanceButton = MinimumTargetButton(configuration: .plain())
    private let header: MessageHeaderView
    private var appearance = MessageAppearance.app
    private let remoteNotice = RemoteImagesNotice()
    private let body: MessageWebView
    private let attachments = AttachmentListView()

    init(attachmentData: @escaping (Attachment, Message.ID) async throws -> Data) {
        body = MessageWebView(attachmentData: attachmentData)
        header = MessageHeaderView(accessory: appearanceButton)
        super.init(frame: .zero)
        surface.backgroundColor = .secondarySystemBackground
        surface.layer.cornerRadius = 24
        surface.layer.cornerCurve = .continuous
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        remoteNotice.onLoad = { [weak self] in self?.onAllowRemoteContent?() }
        remoteNotice.onTrust = { [weak self] in self?.onTrust?($0) }

        header.onFold = { [weak self] in self?.onToggle?() }

        let stack = UIStackView(arrangedSubviews: [header, remoteNotice, body, attachments])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
        ])
        body.onLayout = { [weak self] _, blocked in
            self?.remoteNotice.isHidden = !blocked
            self?.onBodyLayout?()
        }
        remoteNotice.isHidden = true

        var look = UIButton.Configuration.plain()
        look.contentInsets = .zero
        look.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .subheadline)
        look.baseForegroundColor = .secondaryLabel
        appearanceButton.configuration = look
        appearanceButton.setContentHuggingPriority(.required, for: .horizontal)
        appearanceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        appearanceButton.addAction(
            UIAction { [weak self] _ in self?.switchAppearance() }, for: .primaryActionTriggered)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: MessageCardView, _) in
            card.showAppearance()
        }
        showAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(
        _ message: Message, dateText: String, accountEmail: String, accountColor: UIColor, allowsRemoteContent: Bool
    ) {
        header.configure(
            MessageHeader(message), dateText: dateText, accountEmail: accountEmail,
            badge: message.isUnread ? .dot(accountColor) : nil)
        remoteNotice.configure(offers: ImageTrustRule.offers(for: message.from.address))
        body.show(MessageWebView.Content(message: message, allowsRemoteContent: allowsRemoteContent))
        attachments.show(AttachmentListView.listed(in: message))
    }

    /// Light or dark, as the card shows now: the app's appearance, or light while the sun button holds it there.
    var shownStyle: UIUserInterfaceStyle {
        surface.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }

    /// The attachment the reader selected with a click, and what opens it in Quick Look.
    var selectedAttachment: (attachment: Attachment, preview: () -> Void)? {
        attachments.selectedChip.map { chip in (chip.attachment, { chip.quickLook() }) }
    }

    /// The next match of `query` in the body, as a box in this card's coordinates.
    func findMatch(_ query: String, backwards: Bool) async -> CGRect? {
        guard let box = await body.findMatch(query, backwards: backwards) else { return nil }
        return body.convert(box, to: self)
    }

    func clearMatch() async {
        await body.clearMatch()
    }

    func setLoading(_ loading: Bool, for attachment: Attachment) {
        attachments.setLoading(loading, for: attachment)
    }

    /// The card crossfades to its new appearance; the body's own styles follow its traits without reloading.
    private func switchAppearance() {
        appearance = appearance.switched
        UIView.transition(with: surface, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.showAppearance()
        }
    }

    private func showAppearance() {
        surface.overrideUserInterfaceStyle = appearance.style
        appearanceButton.isHidden = traitCollection.userInterfaceStyle != .dark
        appearanceButton.configuration?.image = UIImage(systemName: appearance.switchSymbol)
        appearanceButton.accessibilityLabel = appearance.switchTitle
        // Shows on iPad with a pointer, and on the Mac.
        appearanceButton.toolTip = appearance.switchTitle
    }
}

/// A message in the thread's history: one line, "Dana Levi — Can we move the review…". Tapping opens it.
final class TimelineRowView: UIControl {
    private let line = UILabel()
    private let date = UILabel()
    private let dot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        line.font = .preferredFont(forTextStyle: .subheadline)
        line.adjustsFontForContentSizeCategory = true
        date.font = .preferredFont(forTextStyle: .footnote)
        date.textColor = .secondaryLabel
        date.adjustsFontForContentSizeCategory = true
        date.setContentHuggingPriority(.required, for: .horizontal)
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        dot.backgroundColor = .tertiaryLabel
        dot.layer.cornerRadius = 3
        // At the accessibility sizes the date goes under the line, which gets two lines instead of a few words.
        let text = UIStackView(arrangedSubviews: [line, date])
        text.spacing = 10
        text.stacksVerticallyAtAccessibilitySizes()
        let stack = UIStackView(arrangedSubviews: [dot, text])
        stack.spacing = 10
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        // The line's attributed text carries its font, which doesn't scale on its own; set it again at the new size.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: TimelineRowView, _) in
            if let shown = view.shown { view.configure(shown.message, dateText: shown.dateText) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    private var shown: (message: Message, dateText: String)?

    func configure(_ message: Message, dateText: String) {
        shown = (message, dateText)
        line.numberOfLines = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 2 : 1
        let summary = message.snippet.isEmpty ? message.subject : message.snippet
        let text = "\(message.from.displayName) — \(summary)"
        line.setContentText(text, alignedToContent: false)
        let attributed = NSMutableAttributedString(attributedString: line.attributedText ?? NSAttributedString())
        attributed.addAttribute(
            .foregroundColor, value: UIColor.secondaryLabel,
            range: NSRange(
                location: (message.from.displayName as NSString).length,
                length: attributed.length
                    - (message.from.displayName as NSString).length))
        line.attributedText = attributed
        date.text = dateText
        accessibilityLabel = "\(message.from.displayName), \(summary), \(dateText)"
        accessibilityUserInputLabels = [message.from.displayName]
    }
}
