/// Where a window's reader goes when the reader asks a change of mail in that window, and only then (R6–R8): the
/// window's one place for it, so the reader never leaves a conversation because sync or another device changed it.
///
/// It remembers the list as it showed when the open conversation opened, so a conversation whose row has left since
/// still has a next one.
public struct ReaderCourse: Equatable, Sendable {
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
    public struct Facts: Equatable, Sendable {
        /// The conversation on show; `nil` with none.
        public var reader: Reader?
        /// The rows of the list the conversation was opened from, top to bottom, as it shows now.
        public var rows: [ThreadSummary.ID]
        /// The rows picked with a pointer beside no conversation, several of them, top to bottom; empty otherwise.
        public var pointerPick: [ThreadSummary.ID]
        /// A message window has no list to go back to or on in.
        public var layout: WindowState.Layout
        public var setting: AfterRemoval

        public init(
            reader: Reader?, rows: [ThreadSummary.ID], pointerPick: [ThreadSummary.ID] = [],
            layout: WindowState.Layout = .viewer, setting: AfterRemoval
        ) {
            self.reader = reader
            self.rows = rows
            self.pointerPick = pointerPick
            self.layout = layout
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
    private struct Trail: Equatable, Sendable {
        let thread: ThreadSummary.ID
        let rows: [ThreadSummary.ID]
    }

    private var trail: Trail?

    public init() {}

    /// `thread` opened from a list showing `rows`.
    public mutating func opened(_ thread: ThreadSummary.ID, from rows: [ThreadSummary.ID]) {
        trail = Trail(thread: thread, rows: rows)
    }

    /// The reader asked `change` of some conversations. Only a change to the conversation on show moves the reader;
    /// with none on show, putting away every row picked with a pointer reads the row after them, so Delete can be
    /// pressed again and again.
    public func asked(_ change: MailChange, _ facts: Facts) -> Move {
        guard let reader = facts.reader else { return afterPick(change, facts) }
        guard change.threads.contains(reader.thread) else { return .stays }
        switch ReaderExit.exit(after: change.request, labels: reader.labels, readIn: reader.mailbox) {
        case .stays:
            return .stays
        case .setAside:
            return facts.layout == .message ? .leavesWindow : .closes
        case .putAway:
            if facts.layout == .message { return .leavesWindow }
            let rows = trail.flatMap { $0.thread == reader.thread ? $0.rows : nil } ?? []
            return move(to: landing(after: change, from: reader.thread, trail: rows, facts))
        }
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

    private func move(to landing: Landing) -> Move {
        switch landing {
        case .thread(let next): .opens(next)
        case .list: .closes
        }
    }
}
