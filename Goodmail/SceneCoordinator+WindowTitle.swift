import MailCore
import MailStore
import MailUI

extension SceneCoordinator {
    /// What the system calls a window showing `state` (`WindowState.windowTitle`).
    func title(of state: WindowState) -> String {
        let subject = state.reading.flatMap { try? model.database.thread($0.thread) }?.subject
        let labels: [MailboxDirectory.Label] =
            switch state.list {
            case .mailbox(let mailbox): labels(naming: mailbox)
            case .scheduled, .snoozed, .smart: []
            }
        let smartMailbox: SmartMailbox? = if case .smart(let id) = state.list { smartMailbox(id) } else { nil }
        return state.windowTitle(
            subject: subject, labels: labels, accounts: model.accounts, smartMailbox: smartMailbox)
    }

    /// The labels of `mailbox`'s account, which name its list when it is one of them.
    func labels(naming mailbox: Mailbox) -> [MailboxDirectory.Label] {
        guard let account = mailbox.accountID, let labels = try? model.database.labels(for: account) else { return [] }
        return labels.map {
            MailboxDirectory.Label(mailbox: Mailbox(labelID: $0.id, accountID: account), name: $0.name, color: nil)
        }
    }
}
