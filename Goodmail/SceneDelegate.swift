import MailCore
import MailUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private enum State {
        /// UIKit hasn't connected the scene yet.
        case notConnected
        /// The database is still opening; the window shows nothing yet. `link` is the link to open once
        /// it has.
        case opening(Task<Void, Never>, link: URL?)
        case running(SceneCoordinator)
        /// The database couldn't open; the window says so.
        case unavailable
    }

    var window: UIWindow?
    private var state = State.notConnected

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Unsafe because `delegate` is unowned. Safe: UIKit keeps the app delegate for the life of the process.
        let launch = (unsafe UIApplication.shared.delegate as! AppDelegate).launch
        // A handoff from another device wins over what this window showed when it was last saved.
        let restoring = (connectionOptions.userActivities + [session.stateRestorationActivity].compactMap(\.self))
            .lazy.compactMap(Self.windowState(in:)).first
        let link = connectionOptions.urlContexts.first?.url
        if let services = launch.running {
            return connect(windowScene, to: services, restoring: restoring, link: link)
        }
        show(LaunchViewController(), in: windowScene)
        state = .opening(
            Task {
                do {
                    let services = try await launch.services()
                    guard case .opening(_, let link) = state else { return }
                    connect(windowScene, to: services, restoring: restoring, link: link)
                } catch {
                    show(LaunchViewController(failure: error), in: windowScene)
                    state = .unavailable
                }
            },
            link: link)
    }

    private func connect(_ windowScene: UIWindowScene, to services: AppServices, restoring: WindowState?, link: URL?) {
        let coordinator = SceneCoordinator(windowScene: windowScene, model: services.model, restoring: restoring)
        state = .running(coordinator)
        coordinator.start()
        if let route = services.routes.takeWaiting() { coordinator.handle(route) }
        coordinator.window.makeKeyAndVisible()
        window?.isHidden = true
        window = coordinator.window
        // Messages open into a web view whose content process takes a while to start; start one now.
        MessageWebViewPool.shared.warmUp()
        // The composer and the transfer screen need a visible window to present on.
        if let link { coordinator.open(link) }
    }

    /// A `mailto:` link or transfer code opened while the window is up, or while the database is still opening.
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard let link = contexts.first?.url else { return }
        switch state {
        case .running(let coordinator): coordinator.open(link)
        case .opening(let task, _): state = .opening(task, link: link)
        case .notConnected, .unavailable: break
        }
    }

    /// Shows `controller` in a window of its own, until the coordinator's window replaces it.
    private func show(_ controller: UIViewController, in windowScene: UIWindowScene) {
        let window = window ?? UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    /// The window's coordinator, once the database has opened.
    var coordinator: SceneCoordinator? {
        guard case .running(let coordinator) = state else { return nil }
        return coordinator
    }

    /// Saved with the scene when the system puts the window away, and handed back to `willConnectTo` with it.
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        coordinator?.activity
    }

    /// The window closed, or the system put it away: its minimized messages are free for another window to take.
    func sceneDidDisconnect(_ scene: UIScene) {
        coordinator?.close()
    }

    /// Handoff into a window that is already open.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let state = Self.windowState(in: userActivity) else { return }
        coordinator?.showHandedOff(state)
    }

    private static func windowState(in activity: NSUserActivity) -> WindowState? {
        guard activity.activityType == WindowState.activityType,
            let saved = activity.userInfo?[WindowState.activityKey] as? Data
        else { return nil }
        return try? WindowState(saved: saved)
    }
}
