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
        /// A second Settings window, which closes as the open one comes forward.
        case closing
        /// UIKit disconnected the scene while the database was still opening: it never fills.
        case disconnected
    }

    /// What a window holds, from the activity it opens or is restored with.
    private enum Kind {
        /// The mail screens, or one conversation, showing what the window last showed, if it was saved, or what
        /// another device or window handed it. `lists` says when a list it names, missing here, counts as gone.
        /// `isNew` says the window wasn't saved at a previous launch, so the system has no frame to restore it at,
        /// even when another window handed it what to show, as New Viewer Window and an arrival do.
        case mail(restoring: WindowState?, lists: WindowState.ListCheck, isNew: Bool)
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
            let isNew = session.stateRestorationActivity == nil
            if let state = handed.lazy.compactMap(WindowState.init).first {
                return .mail(restoring: state, lists: .handedOff, isNew: isNew)
            }
            return .mail(
                restoring: session.stateRestorationActivity.flatMap(WindowState.init), lists: .saved, isNew: isNew)
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
        LaunchInterval.begin()
        // What the session said of a window before is of one that has gone.
        SessionRecord.clear(session)
        let launch = Self.launch
        let arrival =
            connectionOptions.urlContexts.first.map { Arrival.link($0.url) }
            ?? connectionOptions.shortcutItem?.quickAction.map(Arrival.quickAction)
        guard let kind = Kind.of(session, opening: Array(connectionOptions.userActivities)) else {
            state = .closing
            // A window that won't fill hands on what the system opened it for.
            if let arrival { launch.routes.arrive(arrival) }
            return
        }
        // What the system opened the window for waits for it with whatever else arrived from outside, the newest
        // winning.
        if let arrival { launch.routes.hold(arrival) }
        if let services = launch.running {
            return fill(windowScene, with: kind, services: services)
        }
        show(LaunchViewController(), in: windowScene)
        state = .opening(
            Task {
                do {
                    let services = try await launch.services()
                    // The open ignores cancellation, so the scene disconnecting meanwhile is told apart here.
                    guard !Task.isCancelled, case .opening = state else { return }
                    fill(windowScene, with: kind, services: services)
                } catch {
                    guard !Task.isCancelled, case .opening = state else { return }
                    show(LaunchViewController(failure: error), in: windowScene)
                    state = .unavailable
                }
            })
    }

    /// Fills the window with what it holds, once the database is open.
    private func fill(_ windowScene: UIWindowScene, with kind: Kind, services: AppServices) {
        switch kind {
        case .mail(let restoring, let lists, let isNew):
            connect(windowScene, to: services, restoring: restoring, lists: lists, isNew: isNew)
        case .compose(let shown):
            compose(shown, in: windowScene, with: services)
            // What was held for it goes to a mail window (D13).
            services.routes.filled(.otherWork)
        case .settings(let page):
            showSettings(at: page, in: windowScene, with: services)
            services.routes.filled(.otherWork)
        }
    }

    private func connect(
        _ windowScene: UIWindowScene, to services: AppServices, restoring: WindowState?,
        lists: WindowState.ListCheck, isNew: Bool
    ) {
        // Once it shows, which waits for the conversation read to be read off the main actor, what was held meanwhile
        // goes where it belongs: a message window hands it on, and one whose conversation went shows the viewer
        // instead, which takes it.
        let coordinator = SceneCoordinator(
            windowScene: windowScene, model: services.model, restoring: restoring, lists: lists,
            filled: { coordinator in
                guard let arrival = services.routes.filled(coordinator.holds) else { return }
                coordinator.arrive(arrival)
            })
        state = .running(coordinator)
        // A viewer applies what was held for it to what it restored before anything is built, so no restored
        // conversation is built under the arrival's; a screen to present waits in its navigation for the window to be
        // on screen. A message window takes nothing: once it shows, what was held is chosen for again.
        let restoredViewer = coordinator.shown.layout == .viewer
        let handedOff =
            restoredViewer
            ? services.routes.filled(.viewer(reading: nil)).flatMap(coordinator.arriveBeforeShowing) : nil
        coordinator.start()
        coordinator.window.makeKeyAndVisible()
        coordinator.navigator.cameOnScreen()
        // A message window opened from a list keeps the size the system gives it; only a new viewer opens wide.
        ViewerWindowSize.fit(windowScene, isNew: isNew && coordinator.shown.layout == .viewer)
        window?.isHidden = true
        window = coordinator.window
        // Messages open into a web view whose content process takes a while to start; start one now.
        MessageWebViewPool.shared.warmUp()
        if let handedOff { coordinator.arrive(handedOff) }
    }

    /// Fills the window with the one message it holds.
    private func compose(_ shown: ComposeWindow, in windowScene: UIWindowScene, with services: AppServices) {
        let coordinator = ComposeWindowCoordinator(windowScene: windowScene, model: services.model, showing: shown)
        state = .composing(coordinator)
        SessionRecord.set(.composing(coordinator.ticket), on: windowScene.session)
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
    /// mail screens, a message window among them, hands it to the window it belongs in (D13).
    @discardableResult
    private func arrive(_ arrival: Arrival) -> Bool {
        let routes = Self.launch.routes
        switch state {
        case .running(let coordinator):
            if case .message = coordinator.holds { routes.arrive(arrival) } else { coordinator.arrive(arrival) }
        case .opening: routes.hold(arrival)
        case .composing, .settings, .closing: routes.arrive(arrival)
        case .notConnected, .unavailable, .disconnected: return false
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
        case .notConnected, .opening, .unavailable, .closing, .disconnected: nil
        }
    }

    /// The window closed, or the system put it away: its minimized messages are free for another window to take, and
    /// once it held Settings, Settings can open again. One still waiting for the database never fills, so it takes no
    /// window's messages for a window that is gone.
    func sceneDidDisconnect(_ scene: UIScene) {
        SettingsWindowCoordinator.disconnected(scene.session)
        switch state {
        case .running(let coordinator): coordinator.close()
        case .composing(let coordinator): coordinator.close()
        case .settings(let coordinator): coordinator.close()
        case .opening(let waiting):
            waiting.cancel()
            state = .disconnected
            // What arrived for it stays until the system discards the session, as it may connect it again.
            SessionRecord.set(.leftOpening, on: scene.session)
        case .notConnected, .unavailable, .closing, .disconnected: break
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
        case .composing, .settings, .closing, .disconnected: .otherWork
        case .unavailable: .noMail
        }
    }
}
