import MailCore
import MailUI
import UIKit

extension SceneCoordinator {
    /// What fills a window.
    enum Screen {
        /// Before `start()` chose.
        case starting
        /// No account yet: what Goodmail is, and the services to sign in to.
        case welcome(UIViewController)
        /// The other devices' accounts, offered in place of the welcome screen. What follows waits for the reader's
        /// answer.
        case offer(UIViewController)
        /// The mail screens, built for `accounts` so a change another device made rebuilds them. `offer` is the sheet
        /// offering the other devices' accounts while it's up.
        case mailbox(MailSplitViewController, accounts: [AccountID], offer: UIViewController?)
    }
}
