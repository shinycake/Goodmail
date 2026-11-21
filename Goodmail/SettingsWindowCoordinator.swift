import MailCore
import MailUI
import UIKit

/// The one Settings window, where Settings has a window of its own (`SettingsPlacement.ownWindow`): the same screens
/// as the sheet over the mail screens on touch. Sign-ins and transfer codes show over this window. When it closes,
/// every mail window follows what changed while it was up, as one does when the sheet closes.
final class SettingsWindowCoordinator {
    let window: ShakeToUndoWindow
    private let settings: SettingsViewModel
    /// The pages shown over the first screen, which a page asked for while the window is open joins.
    private let pages: SettingsPages

    /// Whether the one Settings window is closed, asked for, or open, across the app's windows. Only `open(at:from:)`,
    /// `connecting(_:)` and `disconnected(_:)` change it.
    private static var state = SettingsWindowState<UISceneSession>.closed

    /// Opens at `page`, the one `connecting(_:)` gave.
    init(windowScene: UIWindowScene, model: AppModel, at page: SettingsPage) {
        pages = SettingsPages(at: page)
        // Settings has nothing a shake could undo, and a desktop window can't be shaken.
        let window = ShakeToUndoWindow(windowScene: windowScene, undo: {})
        self.window = window
        let before = Appearance(model)
        settings = model.settingsViewModel(
            signIn: AccountSignIn(model: model, window: window), transfer: Self.transfer(model, over: window),
            closed: {
                model.shareSettingsNow()
                let changed = Appearance(model) != before
                for mail in MailWindows.all { mail.settingsWindowClosed(changed: changed) }
            })
        window.windowAnswer = { [weak window] command in
            switch command {
            case .closeWindow:
                guard let session = window?.windowScene?.session else { return .unavailable }
                return .ready(perform: { UIApplication.shared.requestSceneSessionDestruction(session, options: nil) })
            case .settings:
                // Already open, and in front.
                return .ready(perform: {})
            default:
                return .notHere
            }
        }
    }

    func start() {
        window.rootViewController = SettingsScreen.window(model: settings, pages: pages)
        window.windowScene?.title = SettingsScreen.title
        // A settings window's size, rather than a mail window's.
        window.windowScene?.sizeRestrictions?.minimumSize = CGSize(width: 520, height: 480)
        window.windowScene?.sizeRestrictions?.maximumSize = CGSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
    }

    /// Saved with the window, so the system restores it as Settings.
    var activity: NSUserActivity { SettingsWindow.activity }

    /// The window closed: Settings is gone.
    func close() {
        settings.didClose()
    }

    /// Shows `page` in the open window, over its first screen.
    func show(_ page: SettingsPage) {
        pages.show(page)
    }

    /// Opens the Settings window at `page` beside `scene`, or brings it forward at `page` when it is already open.
    /// Asked again before the window has connected, it opens that one window, at the page asked for last.
    static func open(at page: SettingsPage, from scene: UIWindowScene?) {
        switch state.request(page) {
        case .open:
            var request = UISceneSessionActivationRequest()
            request.userActivity = SettingsWindow.activity
            activate(request, from: scene)
        case .wait:
            break
        case .raise(let session, let page):
            // A window still waiting for the database opens at its first screen.
            (session.scene?.delegate as? SceneDelegate)?.settingsWindow?.show(page)
            activate(UISceneSessionActivationRequest(session: session), from: scene)
        }
    }

    /// Asks the system to open or raise the window. When it won't, Settings can be asked for again.
    private static func activate(_ request: UISceneSessionActivationRequest, from scene: UIWindowScene?) {
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = scene
        var request = request
        request.options = options
        // UIKit doesn't say which queue the handler runs on; the hop to the main actor is all it does, and it ends
        // there.
        UIApplication.shared.activateSceneSession(for: request) { @Sendable _ in
            Task { @MainActor in SettingsWindowCoordinator.state.requestFailed() }
        }
    }

    /// A Settings window is connecting: the page to open at, or `nil` when another Settings window is open already,
    /// in which case this one closes and that one comes forward.
    static func connecting(_ session: UISceneSession) -> SettingsPage? {
        switch state.connected(session) {
        case .fill(let page):
            return page
        case .duplicate(let open):
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
            activate(UISceneSessionActivationRequest(session: open), from: nil)
            return nil
        }
    }

    /// A window's scene went away, whatever it held: once it is the Settings window, Settings can be asked for again.
    static func disconnected(_ session: UISceneSession) {
        state.closed(session)
    }

    /// Sends and receives accounts by QR code over the Settings window; `nil` in synthetic mailboxes, which have no
    /// sign-ins to move.
    private static func transfer(_ model: AppModel, over window: UIWindow) -> TransferActions? {
        guard model.sharing != nil else { return nil }
        return TransferActions(
            send: { [weak window] in window?.topViewController?.present(TransferScreens.sending(model), animated: true)
            },
            receive: { [weak window] in
                window?.topViewController?.present(TransferScreens.receiving(model).screen, animated: true)
            })
    }
}
