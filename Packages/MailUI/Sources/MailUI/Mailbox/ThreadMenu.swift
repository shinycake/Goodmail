import MailCore
import UIKit

/// What touching and holding a row in the mailbox list offers, in sections: answers, the thread's state, where it
/// goes, then what takes it out of the way here, with Trash last.
struct ThreadMenu: Equatable {
    enum Item: Equatable {
        case answer(Answer)
        case openInNewWindow
        case perform(ThreadAction)
        case snooze
        case move
        case changeLabels
    }

    let sections: [[Item]]

    /// `service` is the thread's account's, or `nil` when the list can't act on its threads, which leaves only the
    /// answers and, with `opensWindows`, Open in New Window.
    init(thread: ThreadSummary, in mailbox: Mailbox, service: MailService?, opensWindows: Bool) {
        // A draft is finished from the reader, not answered.
        let answers: [Item] =
            mailbox.labelID == SystemLabel.draft ? [] : [.answer(.reply), .answer(.replyAll), .answer(.forward)]
        let windows: [Item] = opensWindows ? [.openInNewWindow] : []
        guard let service else {
            sections = [answers, windows].filter { !$0.isEmpty }
            return
        }
        let state: [Item] =
            [.markRead(thread.isUnread), .star(!thread.labelIDs.contains(SystemLabel.starred))].map(Item.perform)
            + [ThreadAction.muting([(thread.labelIDs, service)])].compactMap { $0.map(Item.perform) }
        let organize: [Item] =
            (MailboxViewModel.canSnooze([thread]) ? [.snooze] : []) + [.move, .changeLabels]
        var away = MailboxViewModel.trailingActions(for: thread)
        if thread.labelIDs.isDisjoint(with: [SystemLabel.spam, SystemLabel.trash]) {
            away.insert(.reportSpam, at: away.firstIndex(of: .trash) ?? away.endIndex)
        }
        sections = [answers, windows, state, organize, away.map(Item.perform)].filter { !$0.isEmpty }
    }
}

extension MailboxViewModel {
    /// The context menu for `thread`'s row.
    func menu(for thread: ThreadSummary) -> ThreadMenu {
        ThreadMenu(
            thread: thread, in: mailbox, service: actions == nil ? nil : services[thread.id.accountID],
            opensWindows: UIApplication.shared.supportsMultipleScenes)
    }
}

extension ThreadMenu {
    /// Says which thread a menu is for, so committing its preview opens that thread.
    nonisolated final class Identifier: NSObject, NSCopying {
        let thread: ThreadSummary.ID

        init(_ thread: ThreadSummary.ID) { self.thread = thread }

        func copy(with zone: NSZone? = nil) -> Any { self }
    }

    /// The menu with `thread`'s preview above it, acting through `viewModel`. Thread actions go through `perform`,
    /// so Delete Forever asks first; Snooze's later times open over `presenter`.
    static func configuration(
        for thread: ThreadSummary, viewModel: MailboxViewModel, presenter: UIViewController,
        perform: @escaping (ThreadAction) -> Void
    ) -> UIContextMenuConfiguration? {
        let menu = viewModel.menu(for: thread)
        guard !menu.sections.isEmpty else { return nil }
        let id = thread.id
        return UIContextMenuConfiguration(
            identifier: Identifier(id),
            previewProvider: { [dateText = viewModel.dateText(for: thread)] in
                ThreadPreviewViewController(thread: thread, dateText: dateText)
            },
            actionProvider: { [weak viewModel, weak presenter] _ in
                guard let viewModel, let presenter else { return nil }
                let menuItems = Elements(id: id, viewModel: viewModel, presenter: presenter, perform: perform)
                return UIMenu(
                    children: menu.sections.map { items in
                        UIMenu(
                            options: .displayInline,
                            children: items.map(menuItems.element)
                        )
                    })
            })
    }

    /// Turns menu items into UIKit's, for one thread.
    private struct Elements {
        let id: ThreadSummary.ID
        weak var viewModel: MailboxViewModel?
        let presenter: UIViewController
        let perform: (ThreadAction) -> Void

        func element(for item: Item) -> UIMenuElement {
            switch item {
            case .answer(let answer):
                return UIAction(title: answer.title, image: UIImage(systemName: answer.symbol)) { [weak viewModel] _ in
                    viewModel?.answer(id, with: answer)
                }
            case .perform(let action):
                return UIAction(
                    title: action.title, image: UIImage(systemName: action.symbol),
                    attributes: action.isDestructive ? .destructive : []
                ) { _ in perform(action) }
            case .openInNewWindow:
                return UIAction(
                    title: String(
                        localized: "Open in New Window", table: "Mailbox", bundle: .module,
                        comment: "Context menu item that opens a thread in a window of its own"),
                    image: UIImage(systemName: "macwindow.badge.plus")
                ) { [weak viewModel] _ in viewModel?.openInNewWindow(id) }
            case .snooze:
                let times = UIMenu.snooze(from: presenter) { [weak viewModel] in viewModel?.snooze([id], until: $0) }
                return UIMenu(
                    title: String(
                        localized: "Snooze", table: "Mailbox", bundle: .module,
                        comment: "Hides threads until a later time"),
                    image: UIImage(systemName: "clock"), children: times.children)
            case .move:
                return UIAction(
                    title: String(
                        localized: "Move to…", table: "Mailbox", bundle: .module,
                        comment: "Action: move threads to another mailbox"),
                    image: UIImage(systemName: "folder")
                ) { [weak viewModel] _ in viewModel?.move([id]) }
            case .changeLabels:
                return UIAction(
                    title: String(
                        localized: "Change Labels", table: "Mailbox", bundle: .module,
                        comment: "Action: add or remove labels"),
                    image: UIImage(systemName: "tag")
                ) { [weak viewModel] _ in viewModel?.changeLabels(of: [id]) }
            }
        }
    }
}

extension UIAlertController {
    /// Says that a reply or forward from the list found no message to answer, as when it isn't on the device and
    /// can't be fetched.
    public static func answerUnavailable() -> UIAlertController {
        let alert = UIAlertController(
            title: String(
                localized: "Message Not Available", table: "Mailbox", bundle: .module,
                comment: "Alert when a reply or forward can't load the message it answers"),
            message: String(
                localized: "Goodmail couldn't download this message. Check your connection and try again.",
                table: "Mailbox", bundle: .module,
                comment: "Alert when a reply or forward can't load the message it answers"),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(localized: "OK", table: "Mailbox", bundle: .module, comment: "Dismiss"), style: .default))
        return alert
    }
}
