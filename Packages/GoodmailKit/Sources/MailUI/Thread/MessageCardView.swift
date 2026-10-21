import MailCore
import UIKit

/// An open message: a rounded card with who wrote and when, then the body in its own web view.
final class MessageCardView: UIView {
    var onToggle: (() -> Void)?
    var onAllowRemoteContent: (() -> Void)?
    var openURL: ((URL) -> Void)? {
        didSet { body.openURL = openURL }
    }

    private let avatar = MonogramView()
    private let sender = UILabel()
    private let date = UILabel()
    private let recipients = UILabel()
    private let remoteNotice = UIButton(configuration: .plain())
    private let body: MessageWebView

    init(attachmentData: @escaping (Attachment, Message.ID) async throws -> Data) {
        body = MessageWebView(attachmentData: attachmentData)
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous

        sender.font = .preferredFont(forTextStyle: .headline)
        sender.adjustsFontForContentSizeCategory = true
        date.font = .preferredFont(forTextStyle: .subheadline)
        date.textColor = .secondaryLabel
        date.adjustsFontForContentSizeCategory = true
        date.setContentHuggingPriority(.required, for: .horizontal)
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        recipients.font = .preferredFont(forTextStyle: .subheadline)
        recipients.textColor = .secondaryLabel
        recipients.adjustsFontForContentSizeCategory = true

        var notice = UIButton.Configuration.gray()
        notice.cornerStyle = .capsule
        notice.image = UIImage(systemName: "photo.badge.arrow.down")
        notice.imagePadding = 6
        notice.title = String(localized: "Load Remote Images", bundle: .module, comment: "Shows blocked remote content")
        notice.buttonSize = .small
        remoteNotice.configuration = notice
        remoteNotice.isHidden = true
        remoteNotice.addAction(
            UIAction { [weak self] _ in self?.onAllowRemoteContent?() }, for: .primaryActionTriggered)

        let names = UIStackView(arrangedSubviews: [sender, date])
        names.spacing = 8
        names.alignment = .firstBaseline
        let people = UIStackView(arrangedSubviews: [names, recipients])
        people.axis = .vertical
        people.spacing = 2
        let header = UIStackView(arrangedSubviews: [avatar, people])
        header.spacing = 12
        header.alignment = .center
        header.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))

        let noticeRow = UIStackView(arrangedSubviews: [remoteNotice, UIView()])
        let stack = UIStackView(arrangedSubviews: [header, noticeRow, body])
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
            noticeRow.isHidden = !blocked
        }
        noticeRow.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(
        _ message: Message, dateText: String, accountEmail: String, accountColor: UIColor, allowsRemoteContent: Bool
    ) {
        sender.setContentText(message.from.displayName, alignedToContent: false)
        date.text = dateText
        avatar.configure(name: message.from.displayName, badge: message.isUnread ? accountColor : nil)
        recipients.setContentText(Self.recipientsLine(message, accountEmail: accountEmail), alignedToContent: false)
        body.show(MessageWebView.Content(message: message, allowsRemoteContent: allowsRemoteContent))
        accessibilityLabel = [message.from.displayName, dateText].joined(separator: ", ")
    }

    @objc private func toggle() {
        onToggle?()
    }

    /// "to Dana Levi, me": the account's own address reads as "me".
    static func recipientsLine(_ message: Message, accountEmail: String) -> String {
        let me = String(localized: "me", bundle: .module, comment: "The reader, in a recipient list")
        let names = (message.to + message.cc).map { contact in
            contact.address.caseInsensitiveCompare(accountEmail) == .orderedSame ? me : contact.displayName
        }
        return String(
            localized: "to \(names.formatted(.list(type: .and, width: .narrow)))", bundle: .module,
            comment: "Recipients under the sender; the argument is a list of names")
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
