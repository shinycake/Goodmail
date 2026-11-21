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
        /// One conversation alone, in a window of its own (`WindowState.Layout.message`): the reader, built for
        /// `accounts` like the mail screens.
        case message(UIViewController, accounts: [AccountID])
        /// A message window whose thread an action took away, offering to undo it until its toast goes
        /// (`leaveMessage()`). Leaving this screen for any other ends `waiting`.
        case leaving(waiting: Task<Void, Never>)
    }

    /// The accounts the mail on show is built for, while nothing covers it: what may rebuild it, or open Settings over
    /// or beside it. `nil` while the window shows no mail, or something covers it.
    var uncoveredMail: [AccountID]? {
        switch screen {
        case .mailbox(_, let accounts, .none), .message(_, let accounts): accounts
        case .starting, .welcome, .offer, .mailbox, .leaving: nil
        }
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
