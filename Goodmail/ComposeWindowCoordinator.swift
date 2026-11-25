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
/// to the front mail window, whose toast offers Undo Send. With no mail window open, the window stays after Send and
/// offers Undo Send itself until its wait is over, and Undo brings the message back into it.
final class ComposeWindowCoordinator {
    let window: ShakeToUndoWindow
    private let model: AppModel
    private let shown: ComposeWindow
    /// This window's hold on its message's name, which another window of the same name, as one Undo Send reopens while
    /// this one closes, doesn't share. Its scene session keeps it, for when the system discards the window
    /// (`SessionRecord`).
    let ticket: DraftWindowTicket
    private let actions: MailActions
    private let placement: ComposePlacement
    /// New Viewer Window, New Message and Get Mail, with the sync Get Mail starts here.
    private let everyWindow: EveryWindowCommands
    /// Whether the window holds its message yet. Only `start()`, `write(_:holding:)`, `offerUndo()`, `finish()` and
    /// `close()` change it.
    private var state = State.reading

    private enum State {
        /// Reading the message back from where its last window kept it.
        case reading
        case writing(ComposeWindowController)
        /// Sent from here with no mail window to offer Undo Send: the window offers it until the wait is over, then
        /// closes, unless Undo brings the message back (`write(_:)`).
        case sent(Task<Void, Never>)
        /// The message was sent, deleted or saved away, or was gone: the window is closing.
        case done
    }

    init(windowScene: UIWindowScene, model: AppModel, showing shown: ComposeWindow) {
        self.model = model
        self.shown = shown
        ticket = DraftWindowTicket(window: shown.key)
        let actions = MailActions(commands: model.commands)
        self.actions = actions
        everyWindow = EveryWindowCommands(model: model)
        let window = ShakeToUndoWindow(windowScene: windowScene, undo: { actions.undoLast() })
        self.window = window
        // Edit > Undo and ⌘Z take back the window's last action, as a shake does.
        actions.undoManager = window.undoManager
        placement = window.interactionStyle.composePlacement
        window.traitOverrides.senderPictures = model.senderPictures
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .systemBackground
        window.windowAnswer = { [weak self] in self?.windowAnswer(to: $0) ?? .notHere }
        actions.reopen = { [weak self] in self?.undidSend($0) }
    }

    func start() {
        // What was dropped on a mail window for the message comes with it, held in memory, as a drop on a mail
        // window's composer is.
        model.minimizedDrafts.take(for: ticket) { [weak self] drafts, loaded in
            guard let self, case .reading = state else { return }
            guard let draft = drafts.first else { return finish() }
            write(draft, holding: loaded)
        }
    }

    /// Fills the window with a composer for `draft`: the message read back, or one Undo Send took back. `loaded`, what
    /// was dropped on a mail window for it, goes in once the composer is on screen.
    private func write(_ draft: Draft, holding loaded: SharedItems.Loaded? = nil) {
        guard
            let composer = model.composer(
                for: draft, actions: actions,
                sendingThrough: { [weak self, actions] in self?.actionsSending() ?? actions })
        else { return finish() }
        let controller = ComposeWindowController(
            composer: composer, placement: placement, kept: { [weak self] in self?.keepMessage() },
            closed: { [weak self] in self?.composerClosed() },
            onScreen: loaded.map { loaded in { [weak composer] in composer?.start(with: loaded) } })
        state = .writing(controller)
        nameWindow(after: composer)
        window.rootViewController = controller
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
            switch state {
            case .reading, .done:
                // A message not read back yet stays kept, rather than lost with a window closed as it opened.
                break
            case .writing(let controller):
                // Done with before the composer says it closed, so the window doesn't ask to close again.
                state = .done
                controller.composer?.dismissKeepingDraft()
                model.minimizedDrafts.keep([], for: ticket)
            case .sent(let waiting):
                // Closed before the wait was over: the message goes, with nothing left to undo it.
                state = .done
                waiting.cancel()
            }
        }
        model.minimizedDrafts.close(ticket)
    }

    /// Keeps the message as written, under the window's name, and names the window after its subject as it is now.
    private func keepMessage() {
        guard case .writing(let controller) = state, let composer = controller.composer else { return }
        model.minimizedDrafts.keep([composer.written], for: ticket)
        nameWindow(after: composer)
    }

    /// What the system calls the window: the message's subject, or the composer's title, as New Message, until it
    /// has one.
    private func nameWindow(after composer: ComposeViewController) {
        let subject = composer.written.subject
        window.windowScene?.title = subject.isEmpty ? composer.title : subject
    }

    /// Where the message being sent goes to be undone, asked as it is sent. Where every message has a window of its own,
    /// that is the front mail window, whose toast offers Undo Send, or, with none open, this window, which stays to
    /// offer it (`offerUndo()`). Else this window, which closes as it sends.
    private func actionsSending() -> MailActions {
        switch placement {
        case .sheet:
            return actions
        case .ownWindow:
            if let viewer = MailWindows.frontViewer { return viewer.actions }
            offerUndo()
            return actions
        }
    }

    /// Stays open once the composer closes after Send, offering Undo Send in place of the message until the wait is
    /// over, then closes. Undo brings the message back here (`actions.reopen`), and the window stays.
    private func offerUndo() {
        guard case .writing = state else { return }
        // Sent, so a window restored before Undo brings it back has no message to read back.
        model.minimizedDrafts.keep([], for: ticket)
        let actions = actions
        state = .sent(
            Task { [weak self] in
                // Starts once the send is asked for, which follows this at once.
                _ = await actions.waitOutUndo { [weak self] toast in
                    self?.window.rootViewController = UndoCountdown.make(toast, undo: { actions.undoLast() })
                }
                // Undo has put the message back in the window by now; else it went.
                guard let self, case .sent = state else { return }
                finish()
            })
    }

    /// Undo Send took the message back while the window offered it: writing goes on here.
    private func undidSend(_ draft: Draft) {
        guard case .sent = state else { return }
        write(draft)
    }

    /// The composer closed. A message sent with Undo Send to offer here leaves the window to `offerUndo()`.
    private func composerClosed() {
        if case .sent = state { return }
        finish()
    }

    /// The message is done with, or was gone: nothing more to keep, and the window closes. A window already closing
    /// (`close()`) has kept nothing.
    private func finish() {
        if case .done = state { return }
        state = .done
        model.minimizedDrafts.keep([], for: ticket)
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
    /// does, and what every window does (`EveryWindowCommands`).
    private func windowAnswer(to command: MailCommand) -> CommandAnswer {
        switch command {
        case .closeWindow:
            switch state {
            case .writing, .sent: return .ready(perform: { [weak self] in self?.closeWindow() })
            case .reading, .done: return .notHere
            }
        case .settings:
            guard case .ownWindow = window.interactionStyle.settingsPlacement else { return .notHere }
            return .ready(perform: { [weak self] in
                SettingsWindowCoordinator.open(at: .main, from: self?.window.windowScene)
            })
        default:
            return everyWindow.answer(
                to: command, in: window.windowScene,
                newMessage: EveryWindowCommands.newMessageFromMail(placement: placement))
        }
    }
}
