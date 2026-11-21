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
        /// The one Settings window, where Settings has a window of its own.
        case settings(SettingsWindowCoordinator)
        /// The database couldn't open; the window says so.
        case unavailable
    }

    /// What a window holds, from the activity it opens or is restored with.
    private enum Kind {
        /// The mail screens, or one conversation, showing what the window last showed, if it was saved, or what
        /// another device or window handed it. `lists` says when a list it names, missing here, counts as gone.
        case mail(restoring: WindowState?, lists: WindowState.ListCheck)
        case compose(ComposeWindow)
        /// The one Settings window, open at `page`.
        case settings(at: SettingsPage)

        /// What `session` holds, or `nil` for a second Settings window, which closes as the open one comes forward.
        /// `handed` are the activities the window opens with, as a handoff from another device or a window opened
        /// from another, which win over what it showed when it was last saved.
        static func of(_ session: UISceneSession, opening handed: [NSUserActivity]) -> Kind? {
            let activities = handed + [session.stateRestorationActivity].compactMap(\.self)
            if let composing = activities.lazy.compactMap(ComposeWindow.init).first {
                return .compose(composing)
            }
            if activities.contains(where: SettingsWindow.opens) {
                return SettingsWindowCoordinator.connecting(session).map(Kind.settings(at:))
            }
            // A state handed over may name a list this device hasn't synced yet; one saved here named lists it had.
            if let state = handed.lazy.compactMap(WindowState.init).first {
                return .mail(restoring: state, lists: .handedOff)
            }
            return .mail(
                restoring: session.stateRestorationActivity.flatMap(WindowState.init), lists: .saved)
        }
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
        guard let kind = Kind.of(session, opening: Array(connectionOptions.userActivities)) else { return }
        let arrival =
            connectionOptions.urlContexts.first.map { Arrival.link($0.url) }
            ?? connectionOptions.shortcutItem?.quickAction.map(Arrival.quickAction)
        if let services = launch.running {
            return fill(windowScene, with: kind, services: services, arrival: arrival)
        }
        show(LaunchViewController(), in: windowScene)
        state = .opening(
            Task {
                do {
                    let services = try await launch.services()
                    guard case .opening(_, let arrival) = state else { return }
                    fill(windowScene, with: kind, services: services, arrival: arrival)
                } catch {
                    show(LaunchViewController(failure: error), in: windowScene)
                    state = .unavailable
                }
            },
            arrival: arrival)
    }

    /// Fills the window with what it holds, once the database is open.
    private func fill(_ windowScene: UIWindowScene, with kind: Kind, services: AppServices, arrival: Arrival?) {
        switch kind {
        case .mail(let restoring, let lists):
            connect(windowScene, to: services, restoring: restoring, lists: lists, arrival: arrival)
        case .compose(let shown): compose(shown, in: windowScene, with: services)
        case .settings(let page): showSettings(at: page, in: windowScene, with: services)
        }
    }

    private func connect(
        _ windowScene: UIWindowScene, to services: AppServices, restoring: WindowState?,
        lists: WindowState.ListCheck, arrival: Arrival?
    ) {
        let coordinator = SceneCoordinator(
            windowScene: windowScene, model: services.model, restoring: restoring, lists: lists)
        state = .running(coordinator)
        coordinator.start()
        coordinator.window.makeKeyAndVisible()
        ViewerWindowSize.fit(windowScene, isNew: restoring == nil)
        window?.isHidden = true
        window = coordinator.window
        // Once the window is visible, so the route goes to the screens as they are laid out, with Settings or a
        // composer able to present over them.
        if let route = services.routes.takeWaiting() { coordinator.handle(route) }
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

    /// Fills the window with Settings, open at `page`.
    private func showSettings(at page: SettingsPage, in windowScene: UIWindowScene, with services: AppServices) {
        let coordinator = SettingsWindowCoordinator(windowScene: windowScene, model: services.model, at: page)
        state = .settings(coordinator)
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
        case .notConnected, .unavailable, .composing, .settings: break
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
        case .notConnected, .unavailable, .composing, .settings: return false
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

    /// The window's Settings, when it holds them, so a page asked for while it is open shows in it.
    var settingsWindow: SettingsWindowCoordinator? {
        guard case .settings(let coordinator) = state else { return nil }
        return coordinator
    }

    /// Saved with the scene when the system puts the window away, and handed back to `willConnectTo` with it.
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        switch state {
        case .running(let coordinator): coordinator.activity
        case .composing(let coordinator): coordinator.activity
        case .settings(let coordinator): coordinator.activity
        case .notConnected, .opening, .unavailable: nil
        }
    }

    /// The window closed, or the system put it away: its minimized messages are free for another window to take, and
    /// once it held Settings, Settings can open again.
    func sceneDidDisconnect(_ scene: UIScene) {
        SettingsWindowCoordinator.disconnected(scene.session)
        switch state {
        case .running(let coordinator): coordinator.close()
        case .composing(let coordinator): coordinator.close()
        case .settings(let coordinator): coordinator.close()
        case .notConnected, .opening, .unavailable: break
        }
    }

    /// Handoff into a window that is already open.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let state = WindowState(userActivity) else { return }
        coordinator?.showHandedOff(state)
    }
}
