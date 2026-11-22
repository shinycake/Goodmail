import MailCore
import MailStore
import MailUI
import UIKit

extension SceneCoordinator {
    /// What the system calls a window showing `state` (`WindowState.windowTitle`), from what the window already has
    /// rather than the store: the subject from the reader on show, and the label and smart mailbox names from the
    /// sidebar's model, which tells the window when they change (`MailboxesViewModel.namesChanged`).
    func title(of state: WindowState) -> String {
        let subject = readerOnShow.map(\.conversation).flatMap { $0.id == state.reading?.thread ? $0 : nil }?.subject
        let labels: [MailboxDirectory.Label] =
            switch state.list {
            case .mailbox(let mailbox):
                (sidebar?.directory.labels ?? []).filter { $0.mailbox.accountID == mailbox.accountID }
            case .scheduled, .snoozed, .smart: []
            }
        let smartMailbox: SmartMailbox? =
            if case .smart(let id) = state.list { sidebar?.smartDirectory.mailboxes.first { $0.id == id } } else { nil }
        return state.windowTitle(
            subject: subject, labels: labels, accounts: model.accounts, smartMailbox: smartMailbox)
    }

    /// Names the window again, as a label or smart mailbox it names was renamed.
    func retitle() {
        // A message window waiting out its undo keeps the conversation's name: the reader is gone, but Undo brings it
        // back there.
        if case .leaving = screen { return }
        window.windowScene?.title = showsMail ? title(of: shown) : nil
    }

    /// The name of `mailbox`'s list from what the sidebar holds. A label it hasn't named yet, as at a cold launch,
    /// goes untitled rather than by its id until it is named from the store off the main actor.
    func listName(of mailbox: Mailbox) -> (title: String, naming: MailboxViewModel.Naming?) {
        let accounts = model.accounts
        let known = (sidebar?.directory.labels ?? []).filter { $0.mailbox.accountID == mailbox.accountID }
        let title = mailbox.listTitle(labels: known, accounts: accounts)
        guard let account = mailbox.accountID, let id = mailbox.labelID, title == id else { return (title, nil) }
        return (
            "",
            { [database = model.database] in
                guard let labels = try? database.labels(for: account) else { return nil }
                let named = labels.map {
                    MailboxDirectory.Label(
                        mailbox: Mailbox(labelID: $0.id, accountID: account), name: $0.name, color: nil)
                }
                return mailbox.listTitle(labels: named, accounts: accounts)
            }
        )
    }
}
