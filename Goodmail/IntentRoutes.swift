import MailCore
import UIKit

/// Hands routes from intents to a window: the frontmost one, or, when an intent launched the app and no window has
/// connected yet, the first to connect.
final class IntentRoutes {
    /// The route waiting for the first window.
    private var waiting: Route?

    func open(_ route: Route) {
        let scenes =
            UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive } + UIApplication.shared.connectedScenes
        guard let coordinator = scenes.lazy.compactMap({ ($0.delegate as? SceneDelegate)?.coordinator }).first else {
            waiting = route
            return
        }
        coordinator.handle(route)
    }

    /// The route waiting for the window that just connected, which it takes.
    func takeWaiting() -> Route? {
        defer { waiting = nil }
        return waiting
    }
}
