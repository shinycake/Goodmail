import MailCore
import MailUI
import UIKit

extension SceneCoordinator {
    /// What fills a window.
    enum Screen {
        /// Before `start()` chose. `filled` is called as the window leaves it, the first time it fills with a screen.
        case starting(filled: (SceneCoordinator) -> Void)
        /// No account yet: what Goodmail is, and the services to sign in to.
        case welcome(UIViewController)
        /// The other devices' accounts, offered in place of the welcome screen. What follows waits for the reader's
        /// answer.
        case offer(UIViewController)
        /// The mail screens the navigator holds (`WindowNavigator.screens`), and the sheet over them that the
        /// coordinator answers for. `built` is what they were built from, so a change another device or Settings made
        /// to it rebuilds them, and one that changes none of it leaves them be (D9).
        case mailbox(built: Appearance, cover: Cover)
        /// One conversation alone, in a window of its own (`WindowState.Layout.message`): the reader, built from
        /// `built` like the mail screens.
        case message(UIViewController, built: Appearance)
        /// A message window whose thread an action took away, offering to undo it until its toast goes
        /// (`leaveMessage()`). Leaving this screen for any other ends `waiting`.
        case leaving(waiting: Task<Void, Never>)
    }

    /// What the mail on show was built from, while nothing covers it: what may rebuild it, or open Settings over or
    /// beside it. `nil` while the window shows no mail, or something covers it.
    var uncoveredMail: Appearance? {
        switch screen {
        case .mailbox(let built, .none), .message(_, let built): built
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
