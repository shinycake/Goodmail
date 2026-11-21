public import MailCore
public import UIKit

/// What touching and holding a row in the mailbox list offers, in sections: answers, the thread's state, where it
/// goes, then what takes it out of the way here, with Trash last.
struct ThreadMenu: Equatable {
    enum Item: Equatable {
        case answer(Answer)
        case openInNewWindow
        case perform(ThreadAction)
        /// Pin with `true`, Unpin with `false`.
        case pin(Bool)
        case snooze
        case move
        case changeLabels
    }

    /// A section of the menu. The answers and the thread's state sit side by side in one row each, as in Apple Mail,
    /// so the whole menu fits beside the preview on iPad without scrolling Trash out of sight.
    struct Group: Equatable {
        enum Layout: Equatable {
            case row
            case list
        }

        let items: [Item]
        let layout: Layout
    }

    /// What the list can do to its threads.
    enum Reach: Equatable {
        /// Nothing, which leaves only the answers and Open in New Window.
        case readOnly
        /// Everything; `pinned` says whether the thread is pinned, or is `nil` in a list that shows no pins.
        case actions(pinned: Bool?)
    }

    let groups: [Group]

    /// The items of each section, in order.
    var sections: [[Item]] { groups.map(\.items) }

    /// With `opensWindows`, the menu offers Open in New Window.
    init(thread: ThreadSummary, in mailbox: Mailbox, reach: Reach, opensWindows: Bool) {
        // A draft is finished from the reader, not answered.
        let answers: [Item] =
            mailbox.labelID == SystemLabel.draft ? [] : [.answer(.reply), .answer(.replyAll), .answer(.forward)]
        let windows: [Item] = opensWindows ? [.openInNewWindow] : []
        guard case .actions(let pinned) = reach else {
            groups = [Group(items: answers, layout: .row), Group(items: windows, layout: .list)]
                .filter { !$0.items.isEmpty }
            return
        }
        let state: [Item] =
            [.markRead(thread.isUnread), .star(!thread.labelIDs.contains(SystemLabel.starred))].map(Item.perform)
            + [pinned.map { Item.pin(!$0) }].compactMap(\.self)
            + [ThreadAction.muting([thread.labelIDs])].compactMap { $0.map(Item.perform) }
        let place = ThreadPlace(thread, in: mailbox)
        // Snooze takes a thread out of the Inbox, so only the Inbox list offers it, not Trash showing a reply in it.
        let organize: [Item] = (place == .inbox ? [.snooze] : []) + [.move, .changeLabels]
        var away = place.awayActions
        if place.canReportSpam {
            away.insert(.reportSpam, at: away.firstIndex(of: .trash) ?? away.endIndex)
        }
        groups = [
            Group(items: answers, layout: .row), Group(items: windows, layout: .list),
            Group(items: state, layout: .row),
            Group(items: organize, layout: .list), Group(items: away.map(Item.perform), layout: .list),
        ].filter { !$0.items.isEmpty }
    }
}

extension MailboxViewModel {
    /// The context menu for `thread`'s row.
    func menu(for thread: ThreadSummary) -> ThreadMenu {
        ThreadMenu(
            thread: thread, in: mailbox, reach: actions == nil ? .readOnly : .actions(pinned: isPinned(thread.id)),
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
        guard !menu.groups.isEmpty else { return nil }
        let id = thread.id
        return UIContextMenuConfiguration(
            identifier: Identifier(id),
            previewProvider: { [dateText = viewModel.dateText(for: thread)] in
                ThreadPreviewViewController(thread: thread, dateText: dateText)
            },
            actionProvider: { [weak viewModel, weak presenter] _ in
                guard let viewModel, let presenter else { return nil }
                return menu.uiMenu(Elements(ids: [id], viewModel: viewModel, presenter: presenter, perform: perform))
            })
    }

    /// The menu's sections in UIKit's terms, with the sender's commands before what takes the threads away.
    func uiMenu(_ elements: Elements) -> UIMenu {
        var sections = groups.map { group in
            let section = UIMenu(options: .displayInline, children: group.items.map(elements.element))
            if group.layout == .row { section.preferredElementSize = .medium }
            return section
        }
        if let senders = elements.senderSection, !senders.children.isEmpty {
            sections.insert(senders, at: max(sections.endIndex - 1, 0))
        }
        return UIMenu(children: sections)
    }

    /// Turns menu items into UIKit's, for the threads the menu is for. What only one thread can do, as a reply, is
    /// dimmed for several.
    struct Elements {
        let ids: [ThreadSummary.ID]
        weak var viewModel: MailboxViewModel?
        let presenter: UIViewController
        let perform: (ThreadAction) -> Void

        /// The thread, when the menu is for one.
        private var one: ThreadSummary.ID? { ids.count == 1 ? ids.first : nil }
        private var forOneOnly: UIMenuElement.Attributes { one == nil ? .disabled : [] }

        func element(for item: Item) -> UIMenuElement {
            switch item {
            case .answer(let answer):
                return UIAction(
                    title: answer.title, image: UIImage(systemName: answer.symbol), attributes: forOneOnly
                ) { [weak viewModel] _ in
                    if let one { viewModel?.answer(one, with: answer) }
                }
            case .perform(let action):
                return UIAction(
                    title: action.title, image: UIImage(systemName: action.symbol),
                    attributes: action.isDestructive ? .destructive : []
                ) { _ in perform(action) }
            case .pin(let pin):
                return UIAction(
                    title: PinPresentation.title(pin), image: UIImage(systemName: PinPresentation.symbol(pin))
                ) {
                    [weak viewModel] _ in viewModel?.pin(ids, pin)
                }
            case .openInNewWindow:
                return UIAction(
                    title: String(
                        localized: "Open in New Window", table: "Mailbox", bundle: .module,
                        comment: "Context menu item that opens a thread in a window of its own"),
                    image: UIImage(systemName: "macwindow.badge.plus"), attributes: forOneOnly
                ) { [weak viewModel] _ in
                    if let one { viewModel?.openInNewWindow(one) }
                }
            case .snooze:
                let times = UIMenu.snooze(from: presenter) { [weak viewModel] in viewModel?.snooze(ids, until: $0) }
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
                ) { [weak viewModel] _ in viewModel?.move(ids) }
            case .changeLabels:
                return UIAction(
                    title: String(
                        localized: "Change Labels", table: "Mailbox", bundle: .module,
                        comment: "Action: add or remove labels"),
                    image: UIImage(systemName: "tag")
                ) { [weak viewModel] _ in viewModel?.changeLabels(of: ids) }
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
