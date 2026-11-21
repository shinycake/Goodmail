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
        window.windowScene?.title = showsMail ? title(of: shown) : nil
    }

    /// The labels of `mailbox`'s account, which name its list when it is one of them.
    func labels(naming mailbox: Mailbox) -> [MailboxDirectory.Label] {
        guard let account = mailbox.accountID, let labels = try? model.database.labels(for: account) else { return [] }
        return labels.map {
            MailboxDirectory.Label(mailbox: Mailbox(labelID: $0.id, accountID: account), name: $0.name, color: nil)
        }
    }
}
