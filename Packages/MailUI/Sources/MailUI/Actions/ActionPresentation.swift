import MailCore
import UIKit

extension UIBarButtonItem {
    /// Opens the label picker.
    static func changeLabels(_ handler: @escaping () -> Void) -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(
                localized: "Change Labels", table: "Actions", bundle: .module, comment: "Action: add or remove labels"),
            image: UIImage(systemName: "tag"), primaryAction: UIAction { _ in handler() })
    }

    /// Opens the list of places to move threads to.
    static func move(_ handler: @escaping () -> Void) -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(
                localized: "Move to…", table: "Actions", bundle: .module,
                comment: "Action: move threads to another mailbox"),
            image: UIImage(systemName: "folder"), primaryAction: UIAction { _ in handler() })
    }

    /// Move, Change Labels and, when it applies, Mute or Unmute behind one button. The menu asks for `mute` each
    /// time it opens, so it follows the thread as it is then.
    static func organize(
        move: @escaping () -> Void, changeLabels: @escaping () -> Void, mute: @escaping () -> ThreadAction?,
        perform: @escaping (ThreadAction) -> Void
    ) -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(
                localized: "Organize", table: "Actions", bundle: .module,
                comment: "Button: move threads or change labels"),
            image: UIImage(systemName: "folder"),
            menu: UIMenu(children: [
                UIAction(
                    title: String(
                        localized: "Move to…", table: "Actions", bundle: .module,
                        comment: "Action: move threads to another mailbox"),
                    image: UIImage(systemName: "folder")
                ) { _ in move() },
                UIAction(
                    title: String(
                        localized: "Change Labels", table: "Actions", bundle: .module,
                        comment: "Action: add or remove labels"),
                    image: UIImage(systemName: "tag")
                ) { _ in changeLabels() },
                UIDeferredMenuElement.uncached { completion in
                    completion(
                        mute().map { action in
                            [
                                UIAction(title: action.title, image: UIImage(systemName: action.symbol)) { _ in
                                    perform(action)
                                }
                            ]
                        } ?? [])
                },
            ]))
    }
}

extension UIBarButtonItem {
    /// Snooze, with the times on offer when it opens, then a picker for any other.
    static func snooze(from presenter: UIViewController, until: @escaping (Date) -> Void) -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(
                localized: "Snooze", table: "Actions", bundle: .module, comment: "Hides threads until a later time"),
            image: UIImage(systemName: "clock"),
            menu: .snooze(from: presenter, until: until))
    }
}

extension UIMenu {
    static func snooze(from presenter: UIViewController, until: @escaping (Date) -> Void) -> UIMenu {
        UIMenu(
            title: SnoozeTitle.until,
            children: [
                UIDeferredMenuElement.uncached { [weak presenter] completion in
                    let choices = LaterTime.snoozeChoices(at: .now)
                    let times: [UIMenuElement] = choices.map { choice in
                        UIAction(title: choice.title, image: UIImage(systemName: choice.symbol)) { _ in
                            until(choice.date)
                        }
                    }
                    let pick = UIAction(title: SnoozeTitle.chooseTime, image: UIImage(systemName: "calendar")) { _ in
                        guard let presenter else { return }
                        LaterPickerViewController.presentSnooze(
                            from: presenter, initial: choices.first?.date, pick: until)
                    }
                    completion(times + [pick])
                }
            ])
    }
}

extension UIAlertController {
    /// The snooze times as a sheet, for a swipe, which has no menu to open. On iPad it points at `source`.
    static func snooze(from presenter: UIViewController, source: UIView, until: @escaping (Date) -> Void)
        -> UIAlertController
    {
        let sheet = UIAlertController(title: SnoozeTitle.until, message: nil, preferredStyle: .actionSheet)
        let choices = LaterTime.snoozeChoices(at: .now)
        for choice in choices {
            sheet.addAction(UIAlertAction(title: choice.title, style: .default) { _ in until(choice.date) })
        }
        sheet.addAction(
            UIAlertAction(title: SnoozeTitle.chooseTime, style: .default) { [weak presenter] _ in
                guard let presenter else { return }
                LaterPickerViewController.presentSnooze(from: presenter, initial: choices.first?.date, pick: until)
            })
        sheet.addAction(
            UIAlertAction(
                title: String(
                    localized: "Cancel", table: "Actions", bundle: .module, comment: "Closes a menu without acting"),
                style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        return sheet
    }
}

extension LaterPickerViewController {
    static func presentSnooze(from presenter: UIViewController, initial: Date?, pick: @escaping (Date) -> Void) {
        present(
            from: presenter, title: SnoozeTitle.until,
            actionTitle: String(
                localized: "Snooze", table: "Actions", bundle: .module, comment: "Hides threads until a later time"),
            initial: initial, pick: pick)
    }
}

/// The words every way of snoozing shares.
private enum SnoozeTitle {
    static var until: String {
        String(
            localized: "Snooze Until", table: "Actions", bundle: .module,
            comment: "Menu of times to snooze threads until")
    }
    static var chooseTime: String {
        String(
            localized: "Choose a Time…", table: "Actions", bundle: .module,
            comment: "Picks a later time from a calendar")
    }
}

extension ThreadAction {
    private enum Kind {
        case archive, trash, untrash, deleteForever, spam, inbox, read, unread, star, unstar, mute, unmute, labels
    }

    private var kind: Kind {
        switch self {
        case .trash: .trash
        case .untrash: .untrash
        case .deleteForever: .deleteForever
        case .modifyLabels:
            [
                (ThreadAction.archive, Kind.archive), (.reportSpam, .spam), (.moveToInbox, .inbox),
                (.markRead(true), .read), (.markRead(false), .unread), (.star(true), .star), (.star(false), .unstar),
                (.mute, .mute), (.unmute, .unmute),
            ]
            .first { $0.0 == self }?.1 ?? .labels
        }
    }

    /// The box a thread is seen going into when this action puts it away.
    var stow: StowKind? {
        switch kind {
        case .trash: .trash
        case .archive: .archive
        default: nil
        }
    }

    /// The action's name, for buttons and VoiceOver.
    var title: String {
        switch kind {
        case .archive:
            String(localized: "Archive", table: "Actions", bundle: .module, comment: "Action: archive a thread")
        case .trash:
            String(localized: "Trash", table: "Actions", bundle: .module, comment: "Action: move a thread to Trash")
        case .untrash:
            String(
                localized: "Move Out of Trash", table: "Actions", bundle: .module, comment: "Action: restore a thread")
        case .deleteForever:
            String(
                localized: "Delete Forever", table: "DeleteForever", bundle: .module,
                comment: "Action: delete a thread in Trash for good")
        case .spam:
            String(
                localized: "Report Spam", table: "Actions", bundle: .module, comment: "Action: report a thread as spam")
        case .inbox:
            String(localized: "Move to Inbox", table: "Actions", bundle: .module, comment: "Action: back to the Inbox")
        case .read: String(localized: "Mark as Read", table: "Actions", bundle: .module, comment: "Action")
        case .unread: String(localized: "Mark as Unread", table: "Actions", bundle: .module, comment: "Action")
        case .star: String(localized: "Star", table: "Actions", bundle: .module, comment: "Action: star a thread")
        case .unstar:
            String(localized: "Unstar", table: "Actions", bundle: .module, comment: "Action: remove a thread's star")
        case .mute:
            String(
                localized: "Mute", table: "Actions", bundle: .module,
                comment: "Action: keep a thread's replies out of the Inbox")
        case .unmute:
            String(
                localized: "Unmute", table: "Actions", bundle: .module,
                comment: "Action: let a thread's replies reach the Inbox again")
        case .labels:
            String(
                localized: "Change Labels", table: "Actions", bundle: .module, comment: "Action: add or remove labels")
        }
    }

    var symbol: String {
        switch kind {
        case .archive: "archivebox"
        case .trash: "trash"
        case .untrash, .inbox: "tray.and.arrow.down"
        case .deleteForever: "trash.slash"
        case .spam: "xmark.bin"
        case .read: "envelope.open"
        case .unread: "envelope.badge"
        case .star: "star"
        case .unstar: "star.slash"
        case .mute: "bell.slash"
        case .unmute: "bell"
        case .labels: "tag"
        }
    }

    var isDestructive: Bool { [.trash, .deleteForever, .spam].contains(kind) }
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
        undo.title = String(localized: "Undo", table: "Actions", bundle: .module, comment: "Undoes the last action")
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
