/// Where a window's reader goes when the reader asks a change of mail in that window, and only then (R6–R9): the
/// window's one place for it, so the reader never leaves a conversation because sync or another device changed it.
///
/// It remembers the list as it showed when the open conversation opened, so a conversation whose row has left since
/// still has a next one, and the conversation the reader last left, so Undo can bring the reader back to it.
public struct ReaderCourse: Sendable {
    /// The conversation on show, and how its reader sees it now.
    public struct Reader: Equatable, Sendable {
        public var thread: ThreadSummary.ID
        /// Where it is read, which a label change can take it out of.
        public var mailbox: Mailbox
        /// Its labels before the change applies.
        public var labels: Set<String>

        public init(thread: ThreadSummary.ID, mailbox: Mailbox, labels: Set<String>) {
            self.thread = thread
            self.mailbox = mailbox
            self.labels = labels
        }
    }

    /// What the window knows as the change is asked.
    public struct Facts: Sendable {
        /// The conversation on show; `nil` with none.
        public var reader: Reader?
        /// The rows of the list the conversation was opened from, top to bottom, as it shows now.
        public var rows: [ThreadSummary.ID]
        /// The rows picked with a pointer beside no conversation, several of them, top to bottom; empty otherwise.
        public var pointerPick: [ThreadSummary.ID]
        /// What the window shows. A message window has no list to go back to or on in.
        public var state: WindowState
        public var setting: AfterRemoval

        public init(
            reader: Reader?, rows: [ThreadSummary.ID], pointerPick: [ThreadSummary.ID], state: WindowState,
            setting: AfterRemoval
        ) {
            self.reader = reader
            self.rows = rows
            self.pointerPick = pointerPick
            self.state = state
            self.setting = setting
        }
    }

    /// What the window does with its reader.
    public enum Move: Equatable, Sendable {
        case stays
        /// Back to the list, with nothing open.
        case closes
        /// Reads this conversation of the same list in the reader's place.
        case opens(ThreadSummary.ID)
        /// A message window, which shows nothing else, goes once the change can't be undone (ADR-035).
        case leavesWindow
    }

    /// The list's rows when the conversation `thread` opened.
    private struct Trail: Sendable {
        let thread: ThreadSummary.ID
        let rows: [ThreadSummary.ID]
    }

    /// The conversation the reader last left, and the window as leaving it left the window (R9).
    private struct Departure: Sendable {
        let change: MailChange
        let thread: ThreadSummary.ID
        let mailbox: Mailbox
        let landed: WindowState
    }

    private var trail: Trail?
    /// Only until the next change the reader asks: Undo then takes back that one instead.
    private var departure: Departure?

    public init() {}

    /// `thread` opened from a list showing `rows`.
    public mutating func opened(_ thread: ThreadSummary.ID, from rows: [ThreadSummary.ID]) {
        trail = Trail(thread: thread, rows: rows)
    }

    /// The reader asked `change` of some conversations. Only a change to the conversation on show moves the reader;
    /// with none on show, putting away every row picked with a pointer reads the row after them, so Delete can be
    /// pressed again and again.
    public mutating func asked(_ change: MailChange, _ facts: Facts) -> Move {
        departure = nil
        guard let reader = facts.reader else { return afterPick(change, facts) }
        guard change.threads.contains(reader.thread) else { return .stays }
        let landing: Landing
        switch ReaderExit.exit(after: change.request, labels: reader.labels, readIn: reader.mailbox) {
        case .stays:
            return .stays
        // A message window keeps its own undo, in its place until the toast goes (ADR-035).
        case _ where facts.state.layout == .message:
            return .leavesWindow
        case .setAside:
            landing = .list
        case .putAway:
            let rows = trail.flatMap { $0.thread == reader.thread ? $0.rows : nil } ?? []
            landing = self.landing(after: change, from: reader.thread, trail: rows, facts)
        }
        var landed = facts.state
        let move: Move
        switch landing {
        case .thread(let next):
            landed.setThread(next)
            move = .opens(next)
        case .list:
            landed.setThread(nil)
            move = .closes
        }
        departure = Departure(change: change, thread: reader.thread, mailbox: reader.mailbox, landed: landed)
        return move
    }

    /// Undo took `change` back. The conversation it took the reader from, to read again, while the window shows what
    /// it showed after leaving it: anywhere else, only its row comes back (R9).
    public mutating func undone(_ change: MailChange, in state: WindowState) -> (
        thread: ThreadSummary.ID, mailbox: Mailbox
    )? {
        guard let departure, departure.change == change else { return nil }
        self.departure = nil
        return departure.landed == state ? (departure.thread, departure.mailbox) : nil
    }

    private func afterPick(_ change: MailChange, _ facts: Facts) -> Move {
        guard let anchor = facts.pointerPick.first, Set(facts.pointerPick).isSubset(of: change.threads),
            ReaderExit.exit(after: change.request) == .putAway
        else { return .stays }
        switch landing(after: change, from: anchor, trail: [], facts) {
        case .thread(let next): return .opens(next)
        // Nothing is open to close: the rows leave, and the pick with them.
        case .list: return .stays
        }
    }

    private func landing(
        after change: MailChange, from anchor: ThreadSummary.ID, trail: [ThreadSummary.ID], _ facts: Facts
    ) -> Landing {
        Landing.after(
            putAway: Set(change.threads), anchor: anchor, trail: trail, rows: facts.rows, setting: facts.setting)
    }
}
