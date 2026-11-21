import MailCore
import MailUI
import UIKit

extension SceneCoordinator {
    /// What the window does for a menu bar command or shortcut that no screen has: New Window and Close Window where
    /// the device has windows, and Settings, over the mail screens or in its own window.
    func windowAnswer(to command: MailCommand) -> CommandAnswer {
        switch command {
        case .newWindow:
            guard UIApplication.shared.supportsMultipleScenes, showsMail else { return .unavailable }
            return .ready(perform: { [weak self] in self?.openWindow(showing: WindowState()) {} })
        case .closeWindow:
            guard UIApplication.shared.supportsMultipleScenes, window.windowScene != nil else { return .unavailable }
            return .ready(perform: { [weak self] in self?.closeWindow() })
        case .settings:
            // Over the mail screens with nothing else over them, or from a conversation in a window of its own.
            guard uncoveredMail != nil else { return .unavailable }
            return .ready(perform: { [weak self] in self?.handle(.settings(.main)) })
        default:
            return .notHere
        }
    }

    /// Closes the window, as its close button does.
    func closeWindow() {
        guard let session = window.windowScene?.session else { return }
        UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
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
    /// Moves `draft` into a window of its own, or into this window's composer when the system can't open one: a
    /// message just taken off this window, or, where every message has a window, any new one. It travels with the
    /// minimized messages, under the new window's name, held for that window so no other takes it first, and what was
    /// dropped for it, `loaded`, with it.
    func openComposeWindow(for draft: Draft, holding loaded: SharedItems.Loaded? = nil) {
        let window = ComposeWindow(for: draft.id)
        let minimized = model.minimizedDrafts
        minimized.reserve(window.key)
        minimized.keep([draft], for: window.key)
        ComposeWindowCoordinator.hold(loaded, for: window)
        openWindow(for: window.activity) { [weak self] in
            minimized.keep([], for: window.key)
            minimized.close(window.key)
            ComposeWindowCoordinator.hold(nil, for: window)
            self?.composeHere(draft, holding: loaded)
        }
    }
}
