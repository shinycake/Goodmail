import MailCore
import MailUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private enum State {
        /// UIKit hasn't connected the scene yet.
        case notConnected
        /// The database is still opening; the window shows nothing yet. What arrives meanwhile is held for it
        /// (`IntentRoutes.hold`).
        case opening(Task<Void, Never>)
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

    var window: UIWindow?
    private var state = State.notConnected

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let launch = Self.launch
        guard let kind = Kind.of(session, opening: Array(connectionOptions.userActivities)) else { return }
        // What the system opened the window for waits for it with whatever else arrived from outside, the newest
        // winning.
        if let arrival = connectionOptions.urlContexts.first.map({ Arrival.link($0.url) })
            ?? connectionOptions.shortcutItem?.quickAction.map(Arrival.quickAction)
        {
            launch.routes.hold(arrival)
        }
        if let services = launch.running {
            return fill(windowScene, with: kind, services: services)
        }
        show(LaunchViewController(), in: windowScene)
        state = .opening(
            Task {
                do {
                    let services = try await launch.services()
                    guard case .opening = state else { return }
                    fill(windowScene, with: kind, services: services)
                } catch {
                    show(LaunchViewController(failure: error), in: windowScene)
                    state = .unavailable
                }
            })
    }

    /// Fills the window with what it holds, once the database is open.
    private func fill(_ windowScene: UIWindowScene, with kind: Kind, services: AppServices) {
        switch kind {
        case .mail(let restoring, let lists):
            connect(windowScene, to: services, restoring: restoring, lists: lists)
        case .compose(let shown):
            compose(shown, in: windowScene, with: services)
            forwardHeldArrival(of: services)
        case .settings(let page):
            showSettings(at: page, in: windowScene, with: services)
            forwardHeldArrival(of: services)
        }
    }

    /// The window that filled holds no mail screens: what was held for it goes to a mail window (D13).
    private func forwardHeldArrival(of services: AppServices) {
        if let held = services.routes.takeArrival() { services.routes.arrive(held) }
    }

    private func connect(
        _ windowScene: UIWindowScene, to services: AppServices, restoring: WindowState?,
        lists: WindowState.ListCheck
    ) {
        let coordinator = SceneCoordinator(
            windowScene: windowScene, model: services.model, restoring: restoring, lists: lists)
        state = .running(coordinator)
        // An arrival that moves the window applies to what it restored before anything is built, so no restored
        // conversation is built under the arrival's; a screen to present waits for the window to be visible.
        let toPresent = services.routes.takeArrival().flatMap(coordinator.arriveBeforeShowing)
        coordinator.start()
        coordinator.window.makeKeyAndVisible()
        ViewerWindowSize.fit(windowScene, isNew: restoring == nil)
        window?.isHidden = true
        window = coordinator.window
        // Messages open into a web view whose content process takes a while to start; start one now.
        MessageWebViewPool.shared.warmUp()
        if let toPresent { coordinator.arrive(toPresent) }
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

    /// A `mailto:` link or transfer code opened while the window is up, or while the database is still opening. A
    /// window holding a message or Settings hands it to a mail window (D13).
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard let link = contexts.first?.url else { return }
        arrive(.link(link))
    }

    /// Takes `arrival`, which the system gave this window, or holds it while the database opens. A window without the
    /// mail screens hands it on.
    @discardableResult
    private func arrive(_ arrival: Arrival) -> Bool {
        let routes = Self.launch.routes
        switch state {
        case .running(let coordinator): coordinator.arrive(arrival)
        case .opening: routes.hold(arrival)
        case .composing, .settings: routes.arrive(arrival)
        case .notConnected, .unavailable: return false
        }
        return true
    }

    /// A Home Screen quick action, while the window is up or the database is still opening. One that launches the
    /// app comes to `willConnectTo` instead.
    func windowScene(
        _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
        guard let action = shortcutItem.quickAction else { return false }
        return arrive(.quickAction(action))
    }

    /// The Home Screen menu is set as the app leaves the foreground, so it matches what the reader left.
    func sceneWillResignActive(_ scene: UIScene) {
        Self.launch.running?.quickActions.refresh()
    }

    /// The app's launch, which opens the database and holds what arrives meanwhile.
    private static var launch: AppLaunch {
        // Unsafe because `delegate` is unowned. Safe: UIKit keeps the app delegate for the life of the process.
        (unsafe UIApplication.shared.delegate as! AppDelegate).launch
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

    /// Handoff into a window that is already open, or held while the database opens.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let state = WindowState(userActivity) else { return }
        arrive(.handoff(state))
    }

    /// What the window holds, as an arrival from outside sees it (`WindowChoice`).
    var holds: WindowFacts.Holds {
        switch state {
        case .notConnected, .opening: .opening
        case .running(let coordinator): coordinator.holds
        case .composing, .settings: .otherWork
        case .unavailable: .noMail
        }
    }
}
