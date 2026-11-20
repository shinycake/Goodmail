import MailCore
import UIKit

/// Hands routes from intents to a window: the frontmost one, or, when an intent launched the app and no window has
/// connected yet, the first to connect.
final class IntentRoutes {
    /// The route waiting for the first window.
    private var waiting: Route?

    func open(_ route: Route) {
        guard let coordinator = frontmost else {
            waiting = route
            return
        }
        coordinator.handle(route)
    }

    /// The thread open in the frontmost window, or `nil` when none is.
    var openThread: ThreadSummary.ID? { MailWindows.frontFirst.first?.openThread }

    /// The coordinator of the frontmost mail window (`MailWindows.frontFirst`). A window that shows one conversation
    /// alone can't go to another thread or mailbox, so one with the mail screens goes first.
    private var frontmost: SceneCoordinator? {
        MailWindows.frontViewer ?? MailWindows.frontFirst.first
    }

    /// The route waiting for the window that just connected, which it takes.
    func takeWaiting() -> Route? {
        defer { waiting = nil }
        return waiting
    }
}
