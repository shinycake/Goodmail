import MailCore
import UIKit

/// A message's new words: what it answers, when that's further up, then its text, with any lines it answers
/// inline set off as quotes. Mine fill with the account's color, theirs with a neutral gray.
final class ChatWordsBubble: UIView, UIContextMenuInteractionDelegate {
    var onShowQuoted: ((Message.ID) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onOpenFull: (() -> Void)?

    private let stack = UIStackView()
    private var shape = ChatBubbleShape(side: .theirs, isFirst: true, isLast: true)
    private var quoted: Message.ID?
    private var text = ""

    init() {
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
        ])
        addInteraction(UIContextMenuInteraction(delegate: self))
        isAccessibilityElement = true
        registerForTraitChanges([UITraitLayoutDirection.self]) { (view: ChatWordsBubble, _) in view.applyShape() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(
        segments: [ReplyText.Segment], quote: ChatTranscript.Quote?, mine: Bool, shape: ChatBubbleShape,
        accountColor: UIColor, voice: String
    ) {
        self.shape = shape
        quoted = quote?.message
        applyShape()
        let fill = mine ? accountColor : .systemGray5
        let ink = mine ? fill.readableInk : .label
        backgroundColor = fill
        for view in stack.arrangedSubviews { view.removeFromSuperview() }

        var spoken = [voice]
        if let quote {
            let name =
                quote.side == .mine
                ? String(
                    localized: "You", table: "Thread", bundle: .module,
                    comment: "VoiceOver: the reader, as the sender of a bubble")
                : quote.sender.displayName
            stack.addArrangedSubview(QuotedReplyView(name: name, excerpt: quote.excerpt, ink: ink))
            spoken.append(
                String(
                    localized: "Replying to \(name): \(quote.excerpt)", table: "Thread", bundle: .module,
                    comment: "VoiceOver: the earlier message a bubble answers"))
        }
        for segment in segments {
            switch segment {
            case .text(let words):
                stack.addArrangedSubview(Self.label(words, style: .body, color: ink))
                spoken.append(words)
            case .quote(let words):
                stack.addArrangedSubview(InlineQuoteView(words, ink: ink))
                spoken.append(
                    String(
                        localized: "Quote: \(words)", table: "Thread", bundle: .module,
                        comment: "VoiceOver: lines a message answers inline"))
            }
        }
        text = segments.map { segment in
            switch segment {
            case .text(let words), .quote(let words): words
            }
        }.joined(separator: "\n\n")
        accessibilityLabel = spoken.joined(separator: ". ")
        accessibilityCustomActions = actions().map { action in
            UIAccessibilityCustomAction(name: action.title) { _ in
                action.perform()
                return true
            }
        }
    }

    private func applyShape() {
        cornerConfiguration = shape.corners(in: effectiveUserInterfaceLayoutDirection)
    }

    static func label(_ text: String, style: UIFont.TextStyle, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        label.setContentText(text)
        // The words wrap within the bubble's widest width, rather than stretch it past it or squeeze it narrower.
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }

    // MARK: Actions

    private struct Action {
        let title: String
        let symbol: String
        let perform: () -> Void
    }

    /// Copy, each link the words hold, the quoted message and the message in full.
    private func actions() -> [Action] {
        var actions = [
            Action(
                title: String(localized: "Copy", table: "Thread", bundle: .module, comment: "Copies a bubble's text"),
                symbol: "doc.on.doc"
            ) { [text] in UIPasteboard.general.string = text }
        ]
        for url in Self.links(in: text).prefix(3) {
            actions.append(
                Action(
                    title: String(
                        localized: "Open \(url.host() ?? url.absoluteString)", table: "Thread", bundle: .module,
                        comment: "Opens a link from a bubble; the argument is the site"),
                    symbol: "safari"
                ) { [weak self] in self?.onOpenURL?(url) })
        }
        if let quoted {
            actions.append(
                Action(
                    title: String(
                        localized: "Go to Quoted Message", table: "Thread", bundle: .module,
                        comment: "Scrolls to the message a bubble answers"),
                    symbol: "arrow.turn.left.up"
                ) { [weak self] in self?.onShowQuoted?(quoted) })
        }
        actions.append(
            Action(
                title: String(
                    localized: "Show Full Message", table: "Thread", bundle: .module,
                    comment: "Opens a bubble's whole email"),
                symbol: "envelope.open"
            ) { [weak self] in self?.onOpenFull?() })
        return actions
    }

    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        let actions = actions()
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(
                children: actions.map { action in
                    UIAction(title: action.title, image: UIImage(systemName: action.symbol)) { _ in action.perform() }
                })
        })
    }
}

/// The earlier message a reply answers, at the top of its bubble: who wrote it and how it began.
private final class QuotedReplyView: UIView {
    init(name: String, excerpt quoted: String, ink: UIColor) {
        super.init(frame: .zero)
        backgroundColor = ink.withAlphaComponent(0.12)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        let sender = ChatWordsBubble.label(name, style: .caption1, color: ink)
        sender.font = UIFont.preferredFont(forTextStyle: .caption1).bold
        let excerpt = ChatWordsBubble.label(quoted, style: .footnote, color: ink.withAlphaComponent(0.8))
        excerpt.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [sender, excerpt])
        stack.axis = .vertical
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
}

/// Lines a message answers inline, set off by a rule on their leading side.
private final class InlineQuoteView: UIView {
    init(_ words: String, ink: UIColor) {
        super.init(frame: .zero)
        let rule = UIView()
        rule.backgroundColor = ink.withAlphaComponent(0.4)
        rule.layer.cornerRadius = 1
        let label = ChatWordsBubble.label(words, style: .subheadline, color: ink.withAlphaComponent(0.75))
        for view in [rule, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.widthAnchor.constraint(equalToConstant: 2),
            label.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
}

/// A message too long or too laid out for a bubble: its subject and first lines, which open the whole letter.
final class ChatLetterBubble: UIControl {
    private let subject = UILabel()
    private let preview = UILabel()
    private let open = UILabel()
    private var shape = ChatBubbleShape(side: .theirs, isFirst: true, isLast: true)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        subject.font = .preferredFont(forTextStyle: .headline)
        subject.numberOfLines = 2
        preview.font = .preferredFont(forTextStyle: .subheadline)
        preview.textColor = .secondaryLabel
        preview.numberOfLines = 4
        open.font = .preferredFont(forTextStyle: .subheadline).bold
        open.textColor = .tintColor
        open.text = String(
            localized: "Open Message", table: "Thread", bundle: .module, comment: "Opens a long message from its bubble"
        )
        for label in [subject, preview, open] {
            label.adjustsFontForContentSizeCategory = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let stack = UIStackView(arrangedSubviews: [subject, preview, open])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(10, after: preview)
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = String(
            localized: "Opens the whole message", table: "Thread", bundle: .module,
            comment: "VoiceOver hint on a long message's bubble")
        registerForTraitChanges([UITraitLayoutDirection.self]) { (view: ChatLetterBubble, _) in view.applyShape() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(subject: String, preview: String, shape: ChatBubbleShape, voice: String) {
        self.shape = shape
        applyShape()
        let title = subject.isEmpty ? ThreadRowMetrics.noSubject : subject
        self.subject.setSubjectText(title)
        self.preview.setContentText(preview.replacingOccurrences(of: "\n", with: " "))
        accessibilityLabel = "\(voice), \(title), \(preview)"
    }

    private func applyShape() {
        cornerConfiguration = shape.corners(in: effectiveUserInterfaceLayoutDirection)
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}

/// A file the message carries, as a glass capsule that opens it.
final class ChatAttachmentBubble: UIButton {
    func configure(_ attachment: Attachment, voice: String) {
        configuration = AttachmentListView.configuration(for: attachment)
        accessibilityLabel = "\(voice), \(attachment.filename), \(AttachmentListView.sizeText(attachment.size))"
    }
}

extension UIColor {
    /// Black or white, whichever reads better on this color, in each appearance.
    var readableInk: UIColor {
        UIColor { traits in
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            self.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: nil)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            return luminance > 0.6 ? .black : .white
        }
    }
}

extension UIFont {
    var bold: UIFont {
        fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}
