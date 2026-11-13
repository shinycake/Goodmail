import MailCore
import UIKit

extension UIBarButtonItem {
    /// Opens the label picker.
    static func changeLabels(_ handler: @escaping () -> Void) -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(localized: "Change Labels", bundle: .module, comment: "Action: add or remove labels"),
            image: UIImage(systemName: "tag"), primaryAction: UIAction { _ in handler() })
    }

    /// Opens the list of places to move threads to.
    static func move(_ handler: @escaping () -> Void) -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(localized: "Move to…", bundle: .module, comment: "Action: move threads to another mailbox"),
            image: UIImage(systemName: "folder"), primaryAction: UIAction { _ in handler() })
    }

    /// Move and Change Labels behind one button, for a toolbar with room for only one of them.
    static func organize(move: @escaping () -> Void, changeLabels: @escaping () -> Void) -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(localized: "Organize", bundle: .module, comment: "Button: move threads or change labels"),
            image: UIImage(systemName: "folder"),
            menu: UIMenu(children: [
                UIAction(
                    title: String(
                        localized: "Move to…", bundle: .module, comment: "Action: move threads to another mailbox"),
                    image: UIImage(systemName: "folder")
                ) { _ in move() },
                UIAction(
                    title: String(localized: "Change Labels", bundle: .module, comment: "Action: add or remove labels"),
                    image: UIImage(systemName: "tag")
                ) { _ in changeLabels() },
            ]))
    }
}

extension UIBarButtonItem {
    /// Snooze, with the times on offer when it opens, then a picker for any other.
    static func snooze(from presenter: UIViewController, until: @escaping (Date) -> Void) -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(localized: "Snooze", bundle: .module, comment: "Hides threads until a later time"),
            image: UIImage(systemName: "clock"),
            menu: .snooze(from: presenter, until: until))
    }
}

extension UIMenu {
    static func snooze(from presenter: UIViewController, until: @escaping (Date) -> Void) -> UIMenu {
        UIMenu(
            title: String(localized: "Snooze Until", bundle: .module, comment: "Menu of times to snooze threads until"),
            children: [
                UIDeferredMenuElement.uncached { [weak presenter] completion in
                    let choices = LaterTime.snoozeChoices(at: .now)
                    let times: [UIMenuElement] = choices.map { choice in
                        UIAction(title: choice.title, image: UIImage(systemName: choice.symbol)) { _ in
                            until(choice.date)
                        }
                    }
                    let pick = UIAction(
                        title: String(
                            localized: "Choose a Time…", bundle: .module, comment: "Picks when a message goes"),
                        image: UIImage(systemName: "calendar")
                    ) { _ in
                        guard let presenter else { return }
                        LaterPickerViewController.present(
                            from: presenter,
                            title: String(
                                localized: "Snooze Until", bundle: .module,
                                comment: "Menu of times to snooze threads until"),
                            actionTitle: String(
                                localized: "Snooze", bundle: .module, comment: "Hides threads until a later time"),
                            initial: choices.first?.date, pick: until)
                    }
                    completion(times + [pick])
                }
            ])
    }
}

extension ThreadAction {
    private enum Kind {
        case archive, trash, untrash, spam, inbox, read, unread, star, unstar, labels
    }

    private var kind: Kind {
        switch self {
        case .trash: .trash
        case .untrash: .untrash
        case .modifyLabels:
            [
                (ThreadAction.archive, Kind.archive), (.reportSpam, .spam), (.moveToInbox, .inbox),
                (.markRead(true), .read), (.markRead(false), .unread), (.star(true), .star), (.star(false), .unstar),
            ]
            .first { $0.0 == self }?.1 ?? .labels
        }
    }

    /// The action's name, for buttons and VoiceOver.
    var title: String {
        switch kind {
        case .archive: String(localized: "Archive", bundle: .module, comment: "Action: archive a thread")
        case .trash: String(localized: "Trash", bundle: .module, comment: "Action: move a thread to Trash")
        case .untrash: String(localized: "Move Out of Trash", bundle: .module, comment: "Action: restore a thread")
        case .spam: String(localized: "Report Spam", bundle: .module, comment: "Action: report a thread as spam")
        case .inbox: String(localized: "Move to Inbox", bundle: .module, comment: "Action: back to the Inbox")
        case .read: String(localized: "Mark as Read", bundle: .module, comment: "Action")
        case .unread: String(localized: "Mark as Unread", bundle: .module, comment: "Action")
        case .star: String(localized: "Star", bundle: .module, comment: "Action: star a thread")
        case .unstar: String(localized: "Unstar", bundle: .module, comment: "Action: remove a thread's star")
        case .labels: String(localized: "Change Labels", bundle: .module, comment: "Action: add or remove labels")
        }
    }

    var symbol: String {
        switch kind {
        case .archive: "archivebox"
        case .trash: "trash"
        case .untrash, .inbox: "tray.and.arrow.down"
        case .spam: "xmark.bin"
        case .read: "envelope.open"
        case .unread: "envelope.badge"
        case .star: "star"
        case .unstar: "star.slash"
        case .labels: "tag"
        }
    }

    var isDestructive: Bool { kind == .trash || kind == .spam }
}

/// The glass capsule along the bottom after an action that hides threads: what happened, and Undo.
final class UndoToastView: UIView {
    var onUndo: (() -> Void)?
    private let label = UILabel()
    private let undoButton = UIButton(configuration: .plain())

    override init(frame: CGRect) {
        super.init(frame: frame)
        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.cornerConfiguration = .capsule()
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        var undo = UIButton.Configuration.plain()
        undo.title = String(localized: "Undo", bundle: .module, comment: "Undoes the last action")
        undo.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            return attributes
        }
        undoButton.configuration = undo
        undoButton.addAction(UIAction { [weak self] _ in self?.onUndo?() }, for: .primaryActionTriggered)
        let stack = UIStackView(arrangedSubviews: [label, undoButton])
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func show(_ message: String) {
        label.text = message
        accessibilityLabel = message
    }
}
