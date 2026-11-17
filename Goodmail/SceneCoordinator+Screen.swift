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
        /// The mail screens, built for `accounts` so a change another device made rebuilds them, and the sheet over
        /// them that the coordinator answers for.
        case mailbox(MailSplitViewController, accounts: [AccountID], cover: Cover)
    }

    /// The sheet over the mail screens that decides what may happen under it.
    enum Cover {
        case none
        /// The other devices' accounts, offered until the reader answers.
        case offer(UIViewController)
        /// Settings, opened at `page`. Nothing rebuilds the mail screens while it's up: closing it does, once, with
        /// everything that changed meanwhile.
        case settings(SettingsPage)
    }
}
