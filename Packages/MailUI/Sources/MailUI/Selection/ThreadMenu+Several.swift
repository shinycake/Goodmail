import MailCore
import UIKit

extension ThreadMenu {
    /// The menu for several threads picked together in a desktop window, in the order of one row's menu, offering what
    /// all of them allow. The answers and Open in New Window stay in their place, dimmed, as they are for one thread
    /// (`Elements`). `pin` is Pin with `true`, Unpin with `false`, or `nil` in a list that shows no pins.
    init(several threads: [ThreadSummary], in mailbox: Mailbox, pin: Bool?, opensWindows: Bool) {
        let answers: [Item] =
            mailbox.labelID == SystemLabel.draft ? [] : [.answer(.reply), .answer(.replyAll), .answer(.forward)]
        let windows: [Item] = opensWindows ? [.openInNewWindow] : []
        let places = threads.map { ThreadPlace($0, in: mailbox) }
        let starred = threads.allSatisfy { $0.labelIDs.contains(SystemLabel.starred) }
        let state: [Item] =
            [.markRead(threads.contains(where: \.isUnread)), .star(!starred)].map(Item.perform)
            + [pin.map(Item.pin)].compactMap(\.self)
            + [ThreadAction.muting(threads.map(\.labelIDs))].compactMap { $0.map(Item.perform) }
        // Labels belong to an account, so the picker opens for one account's threads at a time.
        let oneAccount = Set(threads.map(\.id.accountID)).count == 1
        let organize: [Item] =
            (places.allSatisfy { $0 == .inbox } ? [.snooze] : []) + [.move] + (oneAccount ? [.changeLabels] : [])
        var away = ThreadPlace.awayActions(sharedBy: threads, in: mailbox)
        if places.allSatisfy(\.canReportSpam) {
            away.insert(.reportSpam, at: away.firstIndex(of: .trash) ?? away.endIndex)
        }
        groups = [
            Group(items: answers, layout: .row), Group(items: windows, layout: .list),
            Group(items: state, layout: .row),
            Group(items: organize, layout: .list), Group(items: away.map(Item.perform), layout: .list),
        ].filter { !$0.items.isEmpty }
    }

    /// The menu for `threads`, picked together, acting on all of them through `viewModel`. Thread actions go through
    /// `perform`, so Delete Forever asks first; Snooze's later times open over `presenter`.
    static func configuration(
        forSeveral threads: [ThreadSummary], viewModel: MailboxViewModel, presenter: UIViewController,
        perform: @escaping (ThreadAction) -> Void
    ) -> UIContextMenuConfiguration? {
        let ids = threads.map(\.id)
        guard viewModel.actions != nil else { return nil }
        let menu = ThreadMenu(
            several: threads, in: viewModel.mailbox, pin: viewModel.pinning(ids),
            opensWindows: UIApplication.shared.supportsMultipleScenes)
        return UIContextMenuConfiguration(
            identifier: nil, previewProvider: nil,
            actionProvider: { [weak viewModel, weak presenter] _ in
                guard let viewModel, let presenter else { return nil }
                return menu.uiMenu(Elements(ids: ids, viewModel: viewModel, presenter: presenter, perform: perform))
            })
    }
}
