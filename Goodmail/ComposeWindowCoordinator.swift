import MailCore
import MailUI
import UIKit

/// One per window that holds one message being written (`ComposeWindow`): reads the message back, fills the window
/// with its composer, keeps it as written while the window is away, and closes the window once the message is done
/// with.
final class ComposeWindowCoordinator {
    let window: ShakeToUndoWindow
    private let model: AppModel
    private let shown: ComposeWindow
    private let actions: MailActions
    /// Whether the window holds its message yet. Only `start()` and the composer's closing change it.
    private var state = State.reading

    private enum State {
        /// Reading the message back from where its last window kept it.
        case reading
        case writing(ComposeWindowController)
        /// The message was sent, deleted or saved away, or was gone: the window is closing.
        case done
    }

    init(windowScene: UIWindowScene, model: AppModel, showing shown: ComposeWindow) {
        self.model = model
        self.shown = shown
        let actions = MailActions(commands: model.commands)
        self.actions = actions
        window = ShakeToUndoWindow(windowScene: windowScene, undo: { actions.undoLast() })
        window.traitOverrides.senderPictures = model.senderPictures
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .systemBackground
        window.windowAction = { [weak self] in self?.windowAction(for: $0) }
    }

    func start() {
        model.minimizedDrafts.take(for: shown.key) { [weak self] drafts in
            guard let self, case .reading = state else { return }
            guard let draft = drafts.first, let composer = model.composer(for: draft, actions: actions) else {
                return finish()
            }
            let controller = ComposeWindowController(
                composer: composer, kept: { [weak self] in self?.keepMessage() },
                closed: { [weak self] in self?.finish() })
            state = .writing(controller)
            window.windowScene?.title = draft.subject.isEmpty ? composer.title : draft.subject
            window.rootViewController = controller
        }
    }

    /// Saved with the window when the system puts it away. Keeps the message as written, for the window to read
    /// back when it comes back.
    var activity: NSUserActivity {
        keepMessage()
        return shown.activity
    }

    /// The window is going away: the message stays kept under the window's name, and once no window holds that
    /// name, the next mail window takes it as minimized.
    func close() {
        keepMessage()
        model.minimizedDrafts.close(shown.key)
    }

    private func keepMessage() {
        guard case .writing(let controller) = state, let composer = controller.composer else { return }
        model.minimizedDrafts.keep([composer.written], for: shown.key)
    }

    /// The message is done with, or was gone: nothing more to keep, and the window closes.
    private func finish() {
        state = .done
        model.minimizedDrafts.keep([], for: shown.key)
        closeWindow()
    }

    /// Puts a mail window in this one's place, as Apple Mail does, so closing the message doesn't leave the
    /// person on the Home Screen when this window filled it, then closes this one.
    private func closeWindow() {
        guard let scene = window.windowScene else { return }
        let mail = UIApplication.shared.openSessions.first { session in
            session !== scene.session && session.role == .windowApplication
                && session.stateRestorationActivity.flatMap(ComposeWindow.init) == nil
        }
        if let mail {
            let options = UIScene.ActivationRequestOptions()
            options.requestingScene = scene
            var request = UISceneSessionActivationRequest(session: mail)
            request.options = options
            // Nothing to do when the system won't bring it forward: this window still closes.
            UIApplication.shared.activateSceneSession(for: request, errorHandler: nil)
        }
        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil)
    }

    /// Close Window, from the menu bar or the keyboard, as closing the window from the system's controls does: the
    /// message stays kept, and the next mail window takes it as minimized.
    private func windowAction(for shortcut: KeyboardShortcut) -> (() -> Void)? {
        guard shortcut == .closeWindow, case .writing = state else { return nil }
        return { [weak self] in self?.closeWindow() }
    }
}
