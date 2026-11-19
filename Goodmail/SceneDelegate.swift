import MailCore
import MailUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private enum State {
        /// UIKit hasn't connected the scene yet.
        case notConnected
        /// The database is still opening; the window shows nothing yet. `arrival` is what to open once it has.
        case opening(Task<Void, Never>, arrival: Arrival?)
        case running(SceneCoordinator)
        /// A window that holds one message being written.
        case composing(ComposeWindowCoordinator)
        /// The database couldn't open; the window says so.
        case unavailable
    }

    /// What the window was asked to open as it came up or while the database was opening.
    private enum Arrival {
        /// A `mailto:` link or transfer code.
        case link(URL)
        /// A Home Screen quick action.
        case quickAction(QuickAction)
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
        let activities = connectionOptions.userActivities + [session.stateRestorationActivity].compactMap(\.self)
        let restoring = activities.lazy.compactMap(WindowState.init).first
        let composing = activities.lazy.compactMap(ComposeWindow.init).first
        let arrival =
            connectionOptions.urlContexts.first.map { Arrival.link($0.url) }
            ?? connectionOptions.shortcutItem?.quickAction.map(Arrival.quickAction)
        if let services = launch.running {
            if let composing { return compose(composing, in: windowScene, with: services) }
            return connect(windowScene, to: services, restoring: restoring, arrival: arrival)
        }
        show(LaunchViewController(), in: windowScene)
        state = .opening(
            Task {
                do {
                    let services = try await launch.services()
                    guard case .opening(_, let arrival) = state else { return }
                    if let composing { return compose(composing, in: windowScene, with: services) }
                    connect(windowScene, to: services, restoring: restoring, arrival: arrival)
                } catch {
                    show(LaunchViewController(failure: error), in: windowScene)
                    state = .unavailable
                }
            },
            arrival: arrival)
    }

    private func connect(
        _ windowScene: UIWindowScene, to services: AppServices, restoring: WindowState?, arrival: Arrival?
    ) {
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
        switch arrival {
        case .link(let link): coordinator.open(link)
        case .quickAction(let action): coordinator.perform(action)
        case nil: break
        }
    }

    /// Fills the window with the one message it holds.
    private func compose(_ shown: ComposeWindow, in windowScene: UIWindowScene, with services: AppServices) {
        let coordinator = ComposeWindowCoordinator(windowScene: windowScene, model: services.model, showing: shown)
        state = .composing(coordinator)
        coordinator.start()
        coordinator.window.makeKeyAndVisible()
        window?.isHidden = true
        window = coordinator.window
    }

    /// A `mailto:` link or transfer code opened while the window is up, or while the database is still opening.
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard let link = contexts.first?.url else { return }
        switch state {
        case .running(let coordinator): coordinator.open(link)
        case .opening(let task, _): state = .opening(task, arrival: .link(link))
        case .notConnected, .unavailable, .composing: break
        }
    }

    /// A Home Screen quick action, while the window is up or the database is still opening. One that launches the
    /// app comes to `willConnectTo` instead.
    func windowScene(
        _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
        guard let action = shortcutItem.quickAction else { return false }
        switch state {
        case .running(let coordinator): coordinator.perform(action)
        case .opening(let task, _): state = .opening(task, arrival: .quickAction(action))
        case .notConnected, .unavailable, .composing: return false
        }
        return true
    }

    /// The Home Screen menu is set as the app leaves the foreground, so it matches what the reader left.
    func sceneWillResignActive(_ scene: UIScene) {
        // Unsafe because `delegate` is unowned. Safe: UIKit keeps the app delegate for the life of the process.
        (unsafe UIApplication.shared.delegate as! AppDelegate).launch.running?.quickActions.refresh()
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
        switch state {
        case .running(let coordinator): coordinator.activity
        case .composing(let coordinator): coordinator.activity
        case .notConnected, .opening, .unavailable: nil
        }
    }

    /// The window closed, or the system put it away: its minimized messages are free for another window to take.
    func sceneDidDisconnect(_ scene: UIScene) {
        switch state {
        case .running(let coordinator): coordinator.close()
        case .composing(let coordinator): coordinator.close()
        case .notConnected, .opening, .unavailable: break
        }
    }

    /// Handoff into a window that is already open.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let state = WindowState(userActivity) else { return }
        coordinator?.showHandedOff(state)
    }
}
