import MailCore
import MailUI

extension SceneCoordinator {
    /// A new message holding what another app dropped on the window, from the account being read, as the New Message
    /// button there would start one. What was dropped goes in once the composer is on screen, as a drop on it would:
    /// a title as the subject, words at the top above the signature, files attached.
    func compose(holding loaded: SharedItems.Loaded) {
        guard let account = composingAccount, let composer = composer(for: Draft(accountID: account)) else { return }
        composer.whenOpen { [weak composer] in composer?.receive(loaded) }
        drafts.open(composer)
    }

    /// The account of the thread or mailbox on screen, or the first one where it shows every account's mail.
    var composingAccount: AccountID? {
        if let thread = openThread { return thread.accountID }
        if case .mailbox(let mailbox, _) = shown.list, let account = mailbox.accountID { return account }
        return model.accounts.first?.id
    }
}
