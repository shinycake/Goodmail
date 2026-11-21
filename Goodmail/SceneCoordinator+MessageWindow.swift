import MailCore
import MailUI

extension SceneCoordinator {
    /// An action took the thread out of a message window, which has nothing else to show. The window stays as long as
    /// the action can be undone from its toast, offering Undo in the thread's place, so the undo outlasts the thread
    /// as it does in a mail window. Undo brings the thread back in the window; once the toast goes, or when the action
    /// raised none, the window closes.
    func leaveMessage() {
        let actions = actions
        enter(
            .leaving(
                waiting: Task { [weak self] in
                    let outcome = await actions.waitOutUndo { [weak self] toast in
                        self?.show(UndoCountdown.make(toast, undo: { actions.undoLast() }))
                    }
                    // Anything that took the window elsewhere meanwhile ended the wait.
                    guard let self, case .leaving = screen else { return }
                    switch outcome {
                    case .undone: showMailbox()
                    case .ended, .nothingToUndo: closeWindow()
                    }
                }))
    }
}
