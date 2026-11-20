import MailCore
import MailUI
import UIKit

/// One per window that holds one message being written (`ComposeWindow`): reads the message back, fills the window
/// with its composer, keeps it as written while the window is away, and closes the window once the message is done
/// with.
///
/// What the window is to its message follows from where the window opens new messages (`ComposePlacement`). Where
/// they open in a sheet, as on iPad, the window holds a message moved out of a mail window: closing it keeps the
/// message for the next mail window's drafts pill, and a mail window takes its place. Where every message has a
/// window, as on the Mac, closing it saves the message to Drafts as closing the sheet does, and Send hands the message
/// to the front mail window, whose toast offers Undo Send.
final class ComposeWindowCoordinator {
    let window: ShakeToUndoWindow
    private let model: AppModel
    private let shown: ComposeWindow
    private let actions: MailActions
    private let placement: ComposePlacement
    /// Whether the window holds its message yet. Only `start()`, the composer's closing and `close()` change it.
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
        let window = ShakeToUndoWindow(windowScene: windowScene, undo: { actions.undoLast() })
        self.window = window
        placement = window.interactionStyle.composePlacement
        window.traitOverrides.senderPictures = model.senderPictures
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .systemBackground
        window.windowAnswer = { [weak self] in self?.windowAnswer(to: $0) ?? .notHere }
    }

    func start() {
        model.minimizedDrafts.take(for: shown.key) { [weak self] drafts in
            guard let self, case .reading = state else { return }
            guard let draft = drafts.first,
                let composer = model.composer(
                    for: draft, actions: actions,
                    sendingThrough: { [weak self, actions] in self?.sendingActions ?? actions })
            else {
                return finish()
            }
            let controller = ComposeWindowController(
                composer: composer, kept: { [weak self] in self?.keepMessage() },
                closed: { [weak self] in self?.finish() })
            state = .writing(controller)
            nameWindow(after: composer)
            window.rootViewController = controller
        }
    }

    /// Saved with the window when the system puts it away. Keeps the message as written, for the window to read
    /// back when it comes back.
    var activity: NSUserActivity {
        keepMessage()
        return shown.activity
    }

    /// The window is going away. A message moved out of a mail window stays kept under the window's name, and once
    /// no window holds that name, the next mail window takes it as minimized. Where every message has a window, the
    /// message being written is saved to Drafts, or closes unchanged, as when its sheet is closed, and nothing stays
    /// kept.
    func close() {
        switch placement {
        case .sheet:
            keepMessage()
        case .ownWindow:
            // A message not read back yet stays kept, rather than lost with a window closed as it opened.
            guard case .writing(let controller) = state else { break }
            // Done with before the composer says it closed, so the window doesn't ask to close again.
            state = .done
            controller.composer?.dismissKeepingDraft()
            model.minimizedDrafts.keep([], for: shown.key)
        }
        model.minimizedDrafts.close(shown.key)
    }

    /// Keeps the message as written, under the window's name, and names the window after its subject as it is now.
    private func keepMessage() {
        guard case .writing(let controller) = state, let composer = controller.composer else { return }
        model.minimizedDrafts.keep([composer.written], for: shown.key)
        nameWindow(after: composer)
    }

    /// What the system calls the window: the message's subject, or the composer's title, as New Message, until it
    /// has one.
    private func nameWindow(after composer: ComposeViewController) {
        let subject = composer.written.subject
        window.windowScene?.title = subject.isEmpty ? composer.title : subject
    }

    /// Where a message sent from here goes to be undone: the front mail window, whose toast offers Undo Send, where
    /// every message has a window of its own; else this window, which closes as it sends.
    private var sendingActions: MailActions {
        switch placement {
        case .sheet: actions
        case .ownWindow: MailWindows.frontViewer?.actions ?? actions
        }
    }

    /// The message is done with, or was gone: nothing more to keep, and the window closes. A window already closing
    /// (`close()`) has kept nothing.
    private func finish() {
        if case .done = state { return }
        state = .done
        model.minimizedDrafts.keep([], for: shown.key)
        closeWindow()
    }

    /// Closes the window. Where it holds a message moved out of a mail window, a mail window takes its place first,
    /// as Apple Mail does on iPad, so closing the message doesn't leave the person on the Home Screen when this
    /// window filled it.
    private func closeWindow() {
        guard let scene = window.windowScene else { return }
        if case .sheet = placement { bringMailWindowForward(over: scene) }
        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil)
    }

    private func bringMailWindowForward(over scene: UIWindowScene) {
        let mail = UIApplication.shared.openSessions.first { session in
            session !== scene.session && session.role == .windowApplication
                && session.stateRestorationActivity.flatMap(ComposeWindow.init) == nil
        }
        guard let mail else { return }
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = scene
        var request = UISceneSessionActivationRequest(session: mail)
        request.options = options
        // Nothing to do when the system won't bring it forward: this window still closes.
        UIApplication.shared.activateSceneSession(for: request, errorHandler: nil)
    }

    /// Close Window, from the menu bar or the keyboard, as closing the window from the system's controls does
    /// (`close()`). Settings, where it has a window of its own, which a message window can open as a mail window
    /// does.
    private func windowAnswer(to command: MailCommand) -> CommandAnswer {
        switch command {
        case .closeWindow:
            guard case .writing = state else { return .notHere }
            return .ready(perform: { [weak self] in self?.closeWindow() })
        case .settings:
            guard case .ownWindow = window.interactionStyle.settingsPlacement else { return .notHere }
            return .ready(perform: { [weak self] in SettingsWindowCoordinator.open(from: self?.window.windowScene) })
        default:
            return .notHere
        }
    }
}
