import MailCore
import MailUI
import UIKit

extension SceneCoordinator {
    /// A new message holding what another app dropped on the window, from the account being read, as the New Message
    /// button there would start one: its title as the subject, its words above the signature, its files attached.
    func compose(holding loaded: SharedItems.Loaded) {
        guard let account = composingAccount else { return }
        let content = loaded.content
        let draft = Draft(accountID: account, subject: content.subject, attachments: content.files)
        guard let composer = composer(for: draft, shared: content.body) else { return }
        drafts.open(composer)
        if loaded.leftOutFiles { topViewController()?.present(UIAlertController.fileTooLarge(), animated: true) }
    }

    /// The account of the thread or mailbox on screen, or the first one where it shows every account's mail.
    private var composingAccount: AccountID? {
        if let thread = openThread { return thread.accountID }
        if case .mailbox(let mailbox, _) = shown.list, let account = mailbox.accountID { return account }
        return model.accounts.first?.id
    }
}
