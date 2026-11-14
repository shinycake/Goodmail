import MailCore
import UIKit

/// The bottom of a conversation read as a chat: a message field docked to the keyboard, a + for files, and one
/// glass button that unfolds the mail actions (archive, trash, snooze, reply all…) above the field and folds them
/// away again. Everything sits in one glass container, so the tray grows out of its button as one piece of glass.
final class ChatComposerBar: UIView, UITextViewDelegate {
    /// Sends what was typed and attached. The bar clears itself afterwards.
    var onSend: ((String, [DraftAttachment]) -> Void)?
    /// Tells the reader the bar's height changed, so the conversation keeps clear of it.
    var onResize: (() -> Void)?

    /// Whether the mail actions are unfolded. One place, `setTray`, moves between the two.
    private enum Tray {
        case folded
        case unfolded
    }

    private var tray = Tray.folded
    private var attachments: [DraftAttachment] = []
    private let container = UIVisualEffectView(effect: UIGlassContainerEffect())
    private let actionsGlass = UIVisualEffectView()
    private let actionsRow = UIStackView()
    private let trayButton = UIButton(configuration: .glass())
    private let plusButton = UIButton(configuration: .glass())
    private let fieldGlass = UIVisualEffectView(effect: ChatComposerBar.glass())
    private let textView = UITextView()
    private let placeholder = UILabel()
    /// Filled, not glass: it sits on the field's glass, and glass doesn't stack on glass.
    private let sendButton = UIButton(configuration: .filled())
    private let attachmentsView = ComposeAttachmentsView()
    private lazy var picker = AttachmentPicker { [weak self] in self?.attach($0) }
    private lazy var textHeight = textView.heightAnchor.constraint(equalToConstant: 36)
    /// The tray above the attachments and the field; a hidden row takes no room.
    private lazy var column = UIStackView(arrangedSubviews: [actionsGlass, attachmentsView, row])
    private lazy var row = UIStackView(arrangedSubviews: [trayButton, plusButton, fieldGlass])

    static let maxLines: CGFloat = 6

    init() {
        super.init(frame: .zero)
        configureField()
        configureButtons()
        actionsRow.spacing = 4
        actionsRow.alignment = .center
        actionsRow.distribution = .equalSpacing
        attachmentsView.onRemove = { [weak self] id in
            self?.attachments.removeAll { $0.id == id }
            self?.attachmentsChanged()
        }

        actionsGlass.contentView.addSubview(actionsRow)
        fieldGlass.contentView.addSubview(textView)
        fieldGlass.contentView.addSubview(placeholder)
        fieldGlass.contentView.addSubview(sendButton)
        row.spacing = 8
        row.alignment = .bottom
        column.axis = .vertical
        column.spacing = 10
        column.alignment = .fill
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        container.contentView.addSubview(column)
        addSubview(container)
        for view in [container, column, actionsRow, textView, placeholder, sendButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        let field = fieldGlass.contentView
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: container.contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor),

            actionsRow.topAnchor.constraint(equalTo: actionsGlass.contentView.topAnchor, constant: 4),
            actionsRow.bottomAnchor.constraint(equalTo: actionsGlass.contentView.bottomAnchor, constant: -4),
            actionsRow.leadingAnchor.constraint(equalTo: actionsGlass.contentView.leadingAnchor, constant: 8),
            actionsRow.trailingAnchor.constraint(equalTo: actionsGlass.contentView.trailingAnchor, constant: -8),

            textView.topAnchor.constraint(equalTo: field.topAnchor, constant: 4),
            textView.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -4),
            textView.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -4),
            textHeight,
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
            placeholder.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -4),
            sendButton.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -4),
        ])
        actionsGlass.alpha = 0
        actionsGlass.isHidden = true
        updateSend()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: ChatComposerBar, _) in
            bar.fitText()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// The screen the attachment pickers present from.
    var presenter: UIViewController? {
        get { picker.presenter }
        set { picker.presenter = newValue }
    }

    /// The account's color, for the send button.
    func setAccentColor(_ color: UIColor) {
        sendButton.configuration?.baseBackgroundColor = color
        sendButton.configuration?.baseForegroundColor = color.readableInk
    }

    /// The mail actions the tray unfolds, as the reader's toolbar would show them.
    func setActions(_ items: [UIBarButtonItem]) {
        for view in actionsRow.arrangedSubviews { view.removeFromSuperview() }
        for item in items {
            actionsRow.addArrangedSubview(Self.button(for: item))
        }
    }

    /// Folds the tray and stops preparing attachments: the reader is leaving.
    func finish() {
        setTray(.folded, animated: false)
        picker.finish()
    }

    // MARK: Tray

    private func setTray(_ new: Tray, animated: Bool) {
        guard new != tray else { return }
        tray = new
        let unfolded = new == .unfolded
        trayButton.configuration?.image = UIImage(systemName: unfolded ? "xmark" : "ellipsis")
        trayButton.accessibilityLabel =
            unfolded
            ? String(
                localized: "Hide Mail Actions", table: "Thread", bundle: .module,
                comment: "Folds the chat's mail actions away")
            : String(
                localized: "Mail Actions", table: "Thread", bundle: .module,
                comment: "Unfolds archive, trash and the rest")
        let change = { [self] in
            actionsGlass.isHidden = !unfolded
            actionsGlass.effect = unfolded ? Self.glass() : nil
            actionsGlass.alpha = unfolded ? 1 : 0
            layoutIfNeeded()
            onResize?()
        }
        let focus = {
            UIAccessibility.post(notification: .layoutChanged, argument: unfolded ? self.actionsRow : self.trayButton)
        }
        guard animated else {
            change()
            focus()
            return
        }
        // The glass grows out of its button with a little give; with Reduce Motion it only fades.
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, animations: change, completion: { _ in focus() })
        } else {
            UIView.animate(
                springDuration: 0.45, bounce: 0.2, initialSpringVelocity: 0, delay: 0, options: [],
                animations: change, completion: { _ in focus() })
        }
    }

    // MARK: Field

    private func configureField() {
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        textView.accessibilityLabel = String(
            localized: "Message", table: "Thread", bundle: .module,
            comment: "The chat's reply field, and its placeholder")
        placeholder.text = textView.accessibilityLabel
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = .placeholderText
        placeholder.isAccessibilityElement = false
        fieldGlass.cornerConfiguration = .capsule(maximumRadius: 22)
        actionsGlass.cornerConfiguration = .capsule()
    }

    private func configureButtons() {
        func circle(_ button: UIButton, symbol: String, label: String) {
            button.configuration?.image = UIImage(systemName: symbol)
            button.configuration?.cornerStyle = .capsule
            button.configuration?.baseForegroundColor = .label
            button.accessibilityLabel = label
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 44),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
        }
        circle(
            trayButton, symbol: "ellipsis",
            label: String(
                localized: "Mail Actions", table: "Thread", bundle: .module,
                comment: "Unfolds archive, trash and the rest"))
        trayButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                setTray(tray == .folded ? .unfolded : .folded, animated: true)
            }, for: .primaryActionTriggered)
        circle(
            plusButton, symbol: "plus",
            label: String(localized: "Attach", table: "Thread", bundle: .module, comment: "Adds files to the message"))
        plusButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] in $0(self?.picker.actions() ?? []) }
        ])
        plusButton.showsMenuAsPrimaryAction = true

        sendButton.configuration?.image = UIImage(systemName: "arrow.up")
        sendButton.configuration?.cornerStyle = .capsule
        sendButton.accessibilityIdentifier = "chat.send"
        sendButton.accessibilityLabel = String(
            localized: "Send", table: "Thread", bundle: .module, comment: "Sends the chat reply")
        NSLayoutConstraint.activate([
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .primaryActionTriggered)
    }

    func textViewDidChange(_ textView: UITextView) {
        fitText()
        updateSend()
    }

    /// Grows the field with its text up to `maxLines`, then scrolls inside it.
    private func fitText() {
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        let insets = textView.textContainerInset.top + textView.textContainerInset.bottom
        let maxHeight = (font.lineHeight * Self.maxLines + insets).rounded(.up)
        let width = max(textView.bounds.width, 1)
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = min(max(fitting, font.lineHeight + insets), maxHeight)
        textView.isScrollEnabled = fitting > maxHeight
        guard textHeight.constant != height else { return }
        textHeight.constant = height
        layoutIfNeeded()
        onResize?()
    }

    private var trimmedText: String {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateSend() {
        placeholder.isHidden = !textView.text.isEmpty
        sendButton.isEnabled = !trimmedText.isEmpty || !attachments.isEmpty
    }

    private func attach(_ attachment: DraftAttachment) {
        attachments.append(attachment)
        attachmentsChanged()
    }

    private func attachmentsChanged() {
        attachmentsView.show(attachments)
        updateSend()
        layoutIfNeeded()
        onResize?()
    }

    private func send() {
        guard sendButton.isEnabled else { return }
        onSend?(trimmedText, attachments)
        textView.text = ""
        attachments = []
        attachmentsChanged()
        fitText()
    }

    // MARK: Helpers

    private static func glass() -> UIGlassEffect {
        let glass = UIGlassEffect()
        glass.isInteractive = true
        return glass
    }

    /// A toolbar item as a tray button: its tap, its menu, its symbol, and its title for VoiceOver.
    private static func button(for item: UIBarButtonItem) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = item.image
        configuration.baseForegroundColor = .label
        let button = UIButton(configuration: configuration)
        if let action = item.primaryAction {
            button.addAction(action, for: .primaryActionTriggered)
        }
        button.menu = item.menu
        button.showsMenuAsPrimaryAction = item.primaryAction == nil
        button.accessibilityLabel = item.title ?? item.accessibilityLabel
        button.largeContentTitle = button.accessibilityLabel
        button.showsLargeContentViewer = true
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        return button
    }
}
