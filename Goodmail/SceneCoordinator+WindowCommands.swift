import MailCore
import MailUI
import UIKit

extension SceneCoordinator {
    /// What the window does for a menu bar command or shortcut that no screen has: New Window and Close Window where
    /// the device has windows, and Settings over the mail screens.
    func windowAnswer(to command: MailCommand) -> CommandAnswer {
        switch command {
        case .newWindow:
            guard UIApplication.shared.supportsMultipleScenes, split != nil else { return .unavailable }
            return .ready(perform: { [weak self] in self?.openWindow(showing: WindowState()) {} })
        case .closeWindow:
            guard UIApplication.shared.supportsMultipleScenes, let session = window.windowScene?.session else {
                return .unavailable
            }
            return .ready(perform: { UIApplication.shared.requestSceneSessionDestruction(session, options: nil) })
        case .settings:
            guard case .mailbox(_, _, .none) = screen else { return .unavailable }
            return .ready(perform: { [weak self] in self?.handle(.settings(.main)) })
        default:
            return .notHere
        }
    }

    /// Opens a new window showing `state`, beside this one, or calls `failed` when the system can't open one.
    func openWindow(showing state: WindowState, failed: @escaping @MainActor () -> Void) {
        openWindow(for: state.activity, failed: failed)
    }

    /// Opens a new window for `activity`, beside this one, or calls `failed` when the system can't open one.
    private func openWindow(for activity: NSUserActivity?, failed: @escaping @MainActor () -> Void) {
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = window.windowScene
        var request = UISceneSessionActivationRequest()
        request.userActivity = activity
        request.options = options
        // UIKit doesn't say which queue the handler runs on; the hop to the main actor is all it does, and it ends
        // there.
        UIApplication.shared.activateSceneSession(for: request) { @Sendable _ in
            Task { @MainActor in failed() }
        }
    }
}

extension SceneCoordinator {
    /// Moves `draft`, just taken off this window, into a window of its own, or back here when the system can't open
    /// one. It travels with the minimized messages, under the new window's name, held for that window so no other
    /// takes it first.
    func openComposeWindow(for draft: Draft) {
        let window = ComposeWindow(for: draft.id)
        let minimized = model.minimizedDrafts
        minimized.reserve(window.key)
        minimized.keep([draft], for: window.key)
        openWindow(for: window.activity) { [weak self] in
            minimized.keep([], for: window.key)
            minimized.close(window.key)
            self?.handle(.compose(draft))
        }
    }
}
