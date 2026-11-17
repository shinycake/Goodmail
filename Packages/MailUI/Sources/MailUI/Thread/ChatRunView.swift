import MailCore
import UIKit

/// What a bubble asks the reader for: open a letter or a file, or go to the message a reply quotes; and for a reply
/// of mine still on its way, what its caption offers.
struct ChatBubbleActions {
    var openLetter: (Message.ID) -> Void
    var openAttachment: (Attachment, Message.ID, _ loading: @escaping (Bool) -> Void) -> Void
    var showQuoted: (Message.ID) -> Void
    var openURL: (URL) -> Void
    var pending: ChatDeliveryView.Actions
}

/// One sender's back-to-back bubbles. Mine sit on the trailing side in the account's color; theirs sit on the
/// leading side in gray, beside the sender's avatar, under their name when more than one person writes.
final class ChatRunView: UIView {
    private let column = UIStackView()
    private let name = UILabel()
    private let avatar = ChatAvatarView()
    private var bubbles: [ChatTranscript.Bubble.ID: UIView] = [:]
    /// The caption under each reply of mine still on its way, by the reply.
    private var captions: [Draft.ID: ChatDeliveryView] = [:]
    /// Mine hang from the trailing edge; theirs from beside the avatar.
    private lazy var hangsFromTrailing = column.trailingAnchor.constraint(equalTo: trailingAnchor)
    private lazy var hangsFromAvatar = column.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 8)

    init() {
        super.init(frame: .zero)
        column.axis = .vertical
        column.spacing = 2
        name.font = .preferredFont(forTextStyle: .caption1)
        name.textColor = .secondaryLabel
        name.adjustsFontForContentSizeCategory = true
        name.accessibilityElementsHidden = true
        for view in [column, avatar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            // Bubbles leave the far side open, as a conversation's two sides read.
            column.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatar.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// The view of a bubble shown here, for the reader to scroll to.
    func view(for message: Message.ID) -> UIView? {
        bubbles.first { $0.key.origin == .message(message) && $0.key.attachment == nil }?.value
    }

    func configure(
        _ run: ChatTranscript.Run, isGroup: Bool, accountColor: UIColor, actions: ChatBubbleActions,
        timeText: (Message.ID) -> String
    ) {
        var shownCaptions: [Draft.ID: ChatDeliveryView] = [:]
        defer { captions = shownCaptions }
        let mine = run.side == .mine
        column.alignment = mine ? .trailing : .leading
        avatar.isHidden = mine
        avatar.configure(sender: run.sender)
        hangsFromTrailing.isActive = mine
        hangsFromAvatar.isActive = !mine

        let showsName = !mine && isGroup
        name.setContentText(run.sender.displayName, alignedToContent: false)
        var arranged: [UIView] = showsName ? [name] : []
        if showsName { column.setCustomSpacing(4, after: name) }
        for (index, bubble) in run.bubbles.enumerated() {
            let shape = ChatBubbleShape(
                side: run.side, isFirst: index == 0, isLast: index == run.bubbles.count - 1)
            let sender =
                mine
                ? String(
                    localized: "You", table: "Thread", bundle: .module,
                    comment: "VoiceOver: the reader, as the sender of a bubble")
                : run.sender.displayName
            let status = bubble.message.map(timeText) ?? bubble.delivery.caption ?? ""
            let voice = "\(sender), \(status)"
            let isNew = bubbles[bubble.id] == nil
            let view = bubbleView(for: bubble, mine: mine, actions: actions)
            switch (bubble.content, view) {
            case (.words(let segments, let quote), let view as ChatWordsBubble):
                view.configure(
                    segments: segments, quote: quote, mine: mine, shape: shape, accountColor: accountColor,
                    voice: voice)
            case (.letter(let subject, let preview), let view as ChatLetterBubble):
                view.configure(subject: subject, preview: preview, shape: shape, voice: voice)
            case (.attachment(let attachment), let view as ChatAttachmentBubble):
                view.configure(attachment, voice: voice)
            default:
                break
            }
            ChatDeliveryView.show(bubble.delivery, on: view, arriving: isNew && bubble.message == nil)
            arranged.append(view)
            // The last bubble of a reply on its way says how far it got.
            let next = index + 1 < run.bubbles.count ? run.bubbles[index + 1].origin : nil
            if case .pending(let id) = bubble.origin, next != bubble.origin, bubble.delivery.caption != nil {
                let caption = captions[id] ?? ChatDeliveryView()
                caption.configure(bubble.delivery, reply: id, actions: actions.pending)
                shownCaptions[id] = caption
                arranged.append(caption)
            }
        }
        if arranged != column.arrangedSubviews {
            for view in column.arrangedSubviews { view.removeFromSuperview() }
            arranged.forEach(column.addArrangedSubview)
        }
    }

    private func bubbleView(for bubble: ChatTranscript.Bubble, mine: Bool, actions: ChatBubbleActions) -> UIView {
        if let view = bubbles[bubble.id] { return view }
        let view: UIView
        guard let message = bubble.message else {
            // A reply on its way has nothing to open yet: its words and files read, and its caption offers the rest.
            switch bubble.content {
            case .attachment:
                let file = ChatAttachmentBubble()
                file.isUserInteractionEnabled = false
                view = file
            case .words, .letter:
                view = ChatWordsBubble()
            }
            bubbles[bubble.id] = view
            return view
        }
        switch bubble.content {
        case .words:
            let words = ChatWordsBubble()
            words.onShowQuoted = actions.showQuoted
            words.onOpenURL = actions.openURL
            words.onOpenFull = { actions.openLetter(message) }
            view = words
        case .letter:
            let letter = ChatLetterBubble()
            letter.addAction(UIAction { _ in actions.openLetter(message) }, for: .touchUpInside)
            view = letter
        case .attachment(let attachment):
            let file = ChatAttachmentBubble()
            file.addAction(
                UIAction { [weak file] _ in
                    actions.openAttachment(attachment, message) { file?.showsDownloading($0) }
                }, for: .primaryActionTriggered)
            view = file
        }
        bubbles[bubble.id] = view
        return view
    }
}

/// A bubble's corners: round, except where it meets the bubble above or below it on its sender's side.
struct ChatBubbleShape: Equatable {
    let side: ChatTranscript.Side
    let isFirst: Bool
    let isLast: Bool

    static let radius: CGFloat = 20
    static let joined: CGFloat = 6

    /// Corners on the side the bubbles hang from tighten between bubbles of one run.
    func corners(in direction: UIUserInterfaceLayoutDirection) -> UICornerConfiguration {
        let trailingIsRight = direction == .leftToRight
        let hangsRight = (side == .mine) == trailingIsRight
        let top: UICornerRadius = .fixed(isFirst ? Self.radius : Self.joined)
        let bottom: UICornerRadius = .fixed(isLast ? Self.radius : Self.joined)
        let round: UICornerRadius = .fixed(Self.radius)
        return .corners(
            topLeftRadius: hangsRight ? round : top, topRightRadius: hangsRight ? top : round,
            bottomLeftRadius: hangsRight ? round : bottom, bottomRightRadius: hangsRight ? bottom : round)
    }
}

/// The sender's picture, or their initials in a small neutral circle, beside their last bubble. Tapping it shows who that really is:
/// the name over the address, which a name in a chat could otherwise hide.
final class ChatAvatarView: UIButton {
    static let diameter: CGFloat = 28
    private let initials = UILabel()
    private let picture = UIImageView()
    private let pictureBinding = SenderPictureBinding()
    private var address: String?

    init() {
        super.init(frame: .zero)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = Self.diameter / 2
        showsMenuAsPrimaryAction = true
        initials.font = UIFont.systemFont(ofSize: 11, weight: .semibold).rounded
        initials.textColor = .secondaryLabel
        initials.isUserInteractionEnabled = false
        // Kept at one size to fit the fixed circle, like the list's monograms.
        initials.accessibilityIdentifier = "avatar.initials"
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        picture.layer.cornerRadius = Self.diameter / 2
        picture.isUserInteractionEnabled = false
        picture.accessibilityIgnoresInvertColors = true
        picture.isHidden = true
        // A hairline edge, as on the mailbox rows' pictures.
        picture.layer.borderWidth = 1 / 3
        picture.layer.borderColor = UIColor.separator.cgColor
        for view in [initials, picture] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            initials.centerXAnchor.constraint(equalTo: centerXAnchor),
            initials.centerYAnchor.constraint(equalTo: centerYAnchor),
            picture.leadingAnchor.constraint(equalTo: leadingAnchor),
            picture.trailingAnchor.constraint(equalTo: trailingAnchor),
            picture.topAnchor.constraint(equalTo: topAnchor),
            picture.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        registerForTraitChanges([SenderPicturesTrait.self]) { (view: ChatAvatarView, _) in
            view.bindPicture()
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ChatAvatarView, _) in
            view.picture.layer.borderColor = UIColor.separator.resolvedColor(with: view.traitCollection).cgColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// The small circle still takes a full-size tap.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let grow = max(0, 44 - Self.diameter) / 2
        return bounds.insetBy(dx: -grow, dy: -grow).contains(point)
    }

    func configure(sender: Contact) {
        initials.text = Monogram.initials(for: sender.displayName)
        address = sender.address
        bindPicture()
        accessibilityLabel =
            sender.displayName == sender.address ? sender.address : "\(sender.displayName), \(sender.address)"
        let copy = UIAction(
            title: String(
                localized: "Copy Address", table: "Thread", bundle: .module,
                comment: "Copies a chat sender's email address"),
            subtitle: sender.address, image: UIImage(systemName: "doc.on.doc")
        ) { _ in UIPasteboard.general.string = sender.address }
        menu = UIMenu(title: sender.displayName, children: [copy])
    }
}

extension ChatAvatarView {
    fileprivate func bindPicture() {
        pictureBinding.bind(address: address, pictures: traitCollection.senderPictures) { [weak self] image in
            self?.picture.image = image
            self?.picture.isHidden = image == nil
        }
    }
}

/// "Monday 9:10 AM" between runs, where the conversation paused.
final class ChatTimestampView: UILabel {
    init() {
        super.init(frame: .zero)
        font = .preferredFont(forTextStyle: .caption1)
        textColor = .secondaryLabel
        textAlignment = .center
        adjustsFontForContentSizeCategory = true
        numberOfLines = 0
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
}
