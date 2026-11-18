import MailCore
import MailUI
import UIKit

extension SceneCoordinator {
    /// What the window does for a menu bar command or shortcut that no screen answers, or `nil` when it does nothing
    /// now: New Window and Close Window where the device has windows, and Settings over the mail screens.
    func windowAction(for shortcut: KeyboardShortcut) -> (() -> Void)? {
        switch shortcut {
        case .newWindow:
            guard UIApplication.shared.supportsMultipleScenes, split != nil else { return nil }
            return { [weak self] in self?.openWindow(showing: WindowState()) {} }
        case .closeWindow:
            guard UIApplication.shared.supportsMultipleScenes, let session = window.windowScene?.session else {
                return nil
            }
            return { UIApplication.shared.requestSceneSessionDestruction(session, options: nil) }
        case .settings:
            guard case .mailbox(_, _, .none) = screen else { return nil }
            return { [weak self] in self?.handle(.settings(.main)) }
        case .newMessage, .getMail, .search, .reply, .replyAll, .forward, .archive, .trash, .markUnread, .star, .send,
            .previousThread, .nextThread:
            return nil
        }
    }

    /// Opens a new window showing `state`, beside this one, or calls `failed` when the system can't open one.
    func openWindow(showing state: WindowState, failed: @escaping @MainActor () -> Void) {
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = window.windowScene
        var request = UISceneSessionActivationRequest()
        request.userActivity = state.activity
        request.options = options
        // UIKit doesn't say which queue the handler runs on; the hop to the main actor is all it does, and it ends
        // there.
        UIApplication.shared.activateSceneSession(for: request) { @Sendable _ in
            Task { @MainActor in failed() }
        }
    }
}
