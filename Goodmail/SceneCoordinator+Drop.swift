import MailCore
import MailUI

extension SceneCoordinator {
    /// A new message holding what another app dropped on the window, from the account being read, as the New Message
    /// button there would start one, in this window's composer or a window of its own, as any new message is. What was
    /// dropped goes in once the composer is on screen, as a drop on it would: a title as the subject, words at the top
    /// above the signature, files attached.
    func compose(holding loaded: SharedItems.Loaded) {
        guard let account = composingAccount else { return }
        compose(Draft(accountID: account), holding: loaded)
    }

    /// The account of the thread or mailbox on screen, or the first one where it shows every account's mail.
    var composingAccount: AccountID? {
        if let thread = openThread { return thread.accountID }
        if case .mailbox(let mailbox) = shown.list, let account = mailbox.accountID { return account }
        return model.accounts.first?.id
    }
}
