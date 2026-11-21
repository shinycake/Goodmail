import MailCore
import MailStore
import MailUI

/// A window restored, handed off or rebuilt on a label or smart mailbox deleted since gives way to the Inbox
/// (`WindowState.keeping(_:lists:)`). What is on the device is looked up off the main actor, after the screens are
/// built, so the window shows at once and a gone list is replaced a moment later.
extension SceneCoordinator {
    /// Looks up the labels and smart mailboxes here, and shows the Inbox in place of the shown list if it is gone,
    /// unless the window has moved to another list or other accounts meanwhile. Replaces a look-up under way.
    func fallBackFromGoneList() {
        listsCheck?.cancel()
        let checked = shown.list
        let accounts = model.accounts.map(\.id)
        listsCheck = Task { [weak self, database = model.database] in
            // Only the viewer shows its list; a message window keeps reading where it was opened.
            guard let lists = try? await Self.ownLists(in: database, accounts: accounts), !Task.isCancelled,
                let self, split != nil, shown.list == checked, model.accounts.map(\.id) == accounts
            else { return }
            let kept = shown.keeping(accounts, lists: lists)
            if kept != shown { showMailbox(kept) }
        }
    }

    /// Every label of `accounts` and every smart mailbox stored here.
    @concurrent private static func ownLists(in database: MailDatabase, accounts: [AccountID]) async throws
        -> WindowState.OwnLists
    {
        let labels = try accounts.flatMap { account in
            try database.labels(for: account).map { Mailbox(labelID: $0.id, accountID: account) }
        }
        return WindowState.OwnLists(
            labels: Set(labels), smartMailboxes: Set(try database.smartMailboxes().map(\.id)))
    }
}
