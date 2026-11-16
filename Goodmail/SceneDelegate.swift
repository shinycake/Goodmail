import MailCore
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private enum State {
        /// UIKit hasn't connected the scene yet.
        case notConnected
        /// The database is still opening; the window shows nothing yet.
        case opening(Task<Void, Never>)
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
        if let services = launch.running {
            return connect(windowScene, to: services, restoring: restoring)
        }
        show(LaunchViewController(), in: windowScene)
        state = .opening(
            Task {
                do {
                    connect(windowScene, to: try await launch.services(), restoring: restoring)
                } catch {
                    show(LaunchViewController(failure: error), in: windowScene)
                    state = .unavailable
                }
            })
    }

    private func connect(_ windowScene: UIWindowScene, to services: AppServices, restoring: WindowState?) {
        let coordinator = SceneCoordinator(windowScene: windowScene, model: services.model, restoring: restoring)
        state = .running(coordinator)
        coordinator.start()
        if let route = services.routes.takeWaiting() { coordinator.handle(route) }
        coordinator.window.makeKeyAndVisible()
        window?.isHidden = true
        window = coordinator.window
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
