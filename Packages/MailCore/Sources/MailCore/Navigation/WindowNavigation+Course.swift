extension WindowNavigation {
    /// What the window shows, with what it remembers of how it got there. A course is only ever made from the one
    /// before it, by the transitions below, so what it remembers belongs to what it shows: one showing anything else
    /// starts without Undo's way back and the lookup under way unless the move brings them, and the conversation
    /// read takes how it was opened and what keeps it open with it when another or none is read.
    struct Course: Equatable, Sendable {
        let state: WindowState
        /// How the conversation read was opened and what keeps it open; `nil` while none is read.
        private let reader: ReaderMemory?
        /// The conversation a lookup is under way for, which counts only while the window shows this.
        let lookUp: Awaited?
        /// What the reader left by a change they asked, until the window shows anything else.
        let wayBack: Departure?

        /// What the window remembers of the conversation it reads. It names no conversation: it is the one read.
        private struct ReaderMemory: Equatable, Sendable {
            var opened: Opened?
            /// The reader's own change that took it out of the mailbox it is read in and left them reading it (R8).
            var kept: MailChange?
        }

        /// A window showing `state`, remembering nothing yet.
        init(showing state: WindowState) {
            self.init(state: state, reader: ReaderMemory(), lookUp: nil, wayBack: nil)
        }

        private init(state: WindowState, reader: ReaderMemory?, lookUp: Awaited?, wayBack: Departure?) {
            self.state = state
            self.reader = state.reading == nil ? nil : reader
            self.lookUp = lookUp
            self.wayBack = wayBack
        }

        /// How the conversation read was opened, when the window knows.
        var opened: Opened? { reader?.opened }
        /// The change that keeps the conversation read open though it took it out of where it is read.
        var kept: MailChange? { reader?.kept }

        /// Shows `next`. `opening` is how the conversation it reads was opened, `leaving` Undo's way back to what the
        /// reader left by the move, and `awaiting` a lookup that goes on through it.
        func moved(
            to next: WindowState, opening: Opened? = nil, leaving: Departure? = nil, awaiting: Awaited? = nil
        ) -> Course {
            let stays = next == state
            let readsTheSame = next.reading?.thread == state.reading?.thread
            var memory = readsTheSame ? reader ?? ReaderMemory() : ReaderMemory()
            if let opening { memory.opened = opening }
            return Course(
                state: next, reader: memory, lookUp: awaiting ?? (stays ? lookUp : nil),
                wayBack: leaving ?? (stays ? wayBack : nil))
        }

        /// Waits for `awaited`, in the place of any lookup under way, or for none.
        func lookingUp(_ awaited: Awaited?) -> Course {
            Course(state: state, reader: reader, lookUp: awaited, wayBack: wayBack)
        }

        /// Records what the reader left by a change that moved nothing, or with `nil` forgets it.
        func leaving(_ departure: Departure?) -> Course {
            Course(state: state, reader: reader, lookUp: lookUp, wayBack: departure)
        }

        /// Keeps the conversation read open through `change`, or with `nil` lets the store close it again.
        func keeping(through change: MailChange?) -> Course {
            Course(
                state: state, reader: reader.map { ReaderMemory(opened: $0.opened, kept: change) }, lookUp: lookUp,
                wayBack: wayBack)
        }
    }
}

/// The window's moves, each a transition of its course.
extension WindowNavigation {
    /// Shows `next`, as `Course.moved(to:opening:leaving:awaiting:)` says.
    mutating func move(
        to next: WindowState, opening: Opened? = nil, leaving: Departure? = nil, awaiting: Awaited? = nil
    ) {
        course = course.moved(to: next, opening: opening, leaving: leaving, awaiting: awaiting)
    }

    /// Changes what shows by `change`, as `move(to:opening:leaving:awaiting:)` does.
    mutating func move(opening: Opened? = nil, leaving: Departure? = nil, _ change: (inout WindowState) -> Void) {
        var next = state
        change(&next)
        move(to: next, opening: opening, leaving: leaving)
    }

    /// Looks `awaited` up in the place of any lookup under way.
    mutating func beginLookUp(_ awaited: Awaited) {
        course = course.lookingUp(awaited)
    }

    /// Stops waiting for the lookup under way, if any, so its answer opens nothing.
    mutating func endLookUp() {
        course = course.lookingUp(nil)
    }

    /// Records Undo's way back to what the reader left by a change that moved nothing on show.
    mutating func leave(_ departure: Departure) {
        course = course.leaving(departure)
    }

    /// Ends Undo's way back while what shows stays.
    mutating func endWayBack() {
        course = course.leaving(nil)
    }

    /// Keeps the conversation read open through `change`, which took it out of the mailbox it is read in (R8).
    mutating func keep(through change: MailChange) {
        course = course.keeping(through: change)
    }

    /// Lets the store showing the conversation read out of its mailbox close it again, as once the store shows it
    /// back, or Undo takes back the change that kept it.
    mutating func release() {
        course = course.keeping(through: nil)
    }
}
