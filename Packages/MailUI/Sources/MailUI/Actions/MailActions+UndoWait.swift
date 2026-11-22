import Observation

extension MailActions {
    /// How the chance to undo what was last asked for ended, for a window that stays open to offer it after its own
    /// screen is done, as a message window after Archive or a message's window after Send (`waitOutUndo`).
    public enum UndoWait: Equatable, Sendable {
        /// What was asked raised no toast: it can't be undone, Undo Send is off, or it failed.
        case nothingToUndo
        /// The toast went, with what was done still standing.
        case ended
        /// The reader took it back, from the toast or with a shake.
        case undone
    }

    /// Waits until everything asked for so far is applied and the toast it raised, if any, has gone, then says how it
    /// went. `showing` gets the toast once, as it comes up, to offer it in place of the screen that was done. An
    /// undo asked for meanwhile has been applied by the time this returns, so a message it takes back is in the
    /// composer again (`reopen`).
    public func waitOutUndo(showing: (Toast) -> Void) async -> UndoWait {
        await settled()
        guard let raised = toast, raised.offersUndo else { return .nothingToUndo }
        showing(raised)
        for await shown in Observations({ self.toast?.id }) where shown != raised.id { break }
        await settled()
        // An undo leaves the offer taken; the toast running out leaves it offered, for a shake, or lapsed for a send.
        return undoOffer == .taken ? .undone : .ended
    }
}
