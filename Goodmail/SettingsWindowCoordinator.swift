import MailCore
import MailUI
import UIKit

/// The one Settings window, where Settings has a window of its own (`SettingsPlacement.ownWindow`): the same screens
/// as the sheet over the mail screens on touch. Sign-ins and transfer codes show over this window. When it closes,
/// every mail window follows what changed while it was up, as one does when the sheet closes.
final class SettingsWindowCoordinator {
    let window: ShakeToUndoWindow
    private let settings: SettingsViewModel

    init(windowScene: UIWindowScene, model: AppModel) {
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
        window.rootViewController = SettingsScreen.make(model: settings, placement: .ownWindow)
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

    /// Opens the Settings window beside `scene`, or brings it forward when it is already open.
    static func open(from scene: UIWindowScene?) {
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = scene
        var request: UISceneSessionActivationRequest
        if let open = UIApplication.shared.connectedScenes.first(where: {
            ($0.delegate as? SceneDelegate)?.holdsSettings == true
        }) {
            request = UISceneSessionActivationRequest(session: open.session)
        } else {
            request = UISceneSessionActivationRequest()
            request.userActivity = SettingsWindow.activity
        }
        request.options = options
        // Nothing to do when the system won't open or raise it: the menu item stays, to try again.
        UIApplication.shared.activateSceneSession(for: request, errorHandler: nil)
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
