import MailCore
import UIKit

/// An open message: a rounded card with its header, then the body in its own web view.
final class MessageCardView: UIView {
    var onToggle: (() -> Void)?
    var onAllowRemoteContent: (() -> Void)?
    /// Keeps a rule the reader chose for the sender or their domain, so those remote images always load.
    var onTrust: ((ImageTrustRule) -> Void)?
    var onOpenAttachment: ((Attachment) -> Void)? {
        didSet { attachments.onOpen = onOpenAttachment }
    }
    var openURL: ((URL) -> Void)? {
        didSet { body.openURL = openURL }
    }
    /// Called each time the body takes its height, which can come seconds after the card shows.
    var onBodyLayout: (() -> Void)?

    private let header = MessageHeaderView()
    private let remoteNotice = RemoteImagesNotice()
    private let body: MessageWebView
    private let attachments = AttachmentListView()

    init(attachmentData: @escaping (Attachment, Message.ID) async throws -> Data) {
        body = MessageWebView(attachmentData: attachmentData)
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous

        remoteNotice.onLoad = { [weak self] in self?.onAllowRemoteContent?() }
        remoteNotice.onTrust = { [weak self] in self?.onTrust?($0) }

        header.onFold = { [weak self] in self?.onToggle?() }

        let stack = UIStackView(arrangedSubviews: [header, remoteNotice, body, attachments])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        body.onLayout = { [weak self] _, blocked in
            self?.remoteNotice.isHidden = !blocked
            self?.onBodyLayout?()
        }
        remoteNotice.isHidden = true
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

    func setLoading(_ loading: Bool, for attachment: Attachment) {
        attachments.setLoading(loading, for: attachment)
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
        let stack = UIStackView(arrangedSubviews: [dot, line, date])
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(_ message: Message, dateText: String) {
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
    }
}
