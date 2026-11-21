/// Where a window's reader goes when the reader asks a change of mail in that window, and only then (R6–R9): the
/// window's one place for it, so the reader never leaves a conversation because sync or another device changed it.
///
/// It remembers the list as it showed when the open conversation opened, so a conversation whose row has left since
/// still has a next one, and the conversation the reader last left, so Undo can bring the reader back to it until the
/// window moves on by any other way.
public struct ReaderCourse: Sendable {
    /// The conversation on show, and how its reader sees it now.
    public struct Reader: Equatable, Sendable {
        /// Its row as the reader opened it, which Undo opens it again from without reading the store.
        public var summary: ThreadSummary
        /// Where it is read, which a label change can take it out of.
        public var mailbox: Mailbox
        /// Its labels before the change applies.
        public var labels: Set<String>

        public var thread: ThreadSummary.ID { summary.id }

        public init(_ summary: ThreadSummary, mailbox: Mailbox, labels: Set<String>) {
            self.summary = summary
            self.mailbox = mailbox
            self.labels = labels
        }
    }

    /// The list the window reads conversations from, as it shows now: the narrow stack's, or the one beside the
    /// reader, or the search results over either.
    public struct Front: Equatable, Sendable {
        /// Its rows, top to bottom.
        public var rows: [ThreadSummary.ID]
        /// The rows picked with a pointer beside no conversation, several of them, top to bottom; empty otherwise.
        public var pointerPick: [ThreadSummary.ID]
        /// Where a conversation opened from these rows is read: search results and smart mailboxes read in All Mail.
        public var mailbox: Mailbox

        public init(rows: [ThreadSummary.ID], pointerPick: [ThreadSummary.ID] = [], mailbox: Mailbox) {
            self.rows = rows
            self.pointerPick = pointerPick
            self.mailbox = mailbox
        }
    }

    /// What the window knows as the change is asked.
    public struct Facts: Sendable {
        /// The conversation on show; `nil` with none.
        public var reader: Reader?
        /// The list on show; `nil` for a window that shows none, as a message window.
        public var front: Front?
        /// A message window has no list to go back to or on in.
        public var layout: WindowState.Layout
        public var setting: AfterRemoval

        public init(reader: Reader?, front: Front?, layout: WindowState.Layout, setting: AfterRemoval) {
            self.reader = reader
            self.front = front
            self.layout = layout
            self.setting = setting
        }
    }

    /// A conversation to read, and where it is read.
    public struct Opening: Equatable, Sendable {
        public var thread: ThreadSummary.ID
        public var mailbox: Mailbox

        public init(_ thread: ThreadSummary.ID, in mailbox: Mailbox) {
            self.thread = thread
            self.mailbox = mailbox
        }
    }

    /// What the window does with its reader.
    public enum Move: Equatable, Sendable {
        case stays
        /// Back to the list, with nothing open.
        case closes
        /// Reads this conversation of the list on show in the reader's place.
        case opens(Opening)
        /// A message window, which shows nothing else, goes once the change can't be undone (ADR-035).
        case leavesWindow
    }

    /// The list's rows when the conversation `thread` opened.
    private struct Trail: Sendable {
        let thread: ThreadSummary.ID
        let rows: [ThreadSummary.ID]
    }

    /// The conversation the reader last left, by `change` (R9).
    private struct Departure: Sendable {
        let change: MailChange
        let left: Reader
    }

    private var trail: Trail?
    /// Until the window moves on by any other way: Undo then brings back only the row.
    private var departure: Departure?

    public init() {}

    /// The window opened `thread` from a list showing `rows`, by a tap, a click, an alert or a link: anything but
    /// this course.
    public mutating func opened(_ thread: ThreadSummary.ID, from rows: [ThreadSummary.ID]) {
        trail = Trail(thread: thread, rows: rows)
        departure = nil
    }

    /// The window moved on by itself in any other way: the reader closed, several were picked, another list or
    /// search showed. Undo no longer has a place to bring the reader back to.
    public mutating func navigated() {
        departure = nil
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
        case _ where facts.layout == .message:
            return .leavesWindow
        case .setAside:
            landing = .list
        case .putAway:
            let rows = trail.flatMap { $0.thread == reader.thread ? $0.rows : nil } ?? []
            landing = self.landing(after: change, from: reader.thread, trail: rows, facts)
        }
        departure = Departure(change: change, left: reader)
        guard case .thread(let next) = landing, let front = facts.front else { return .closes }
        trail = Trail(thread: next, rows: front.rows)
        return .opens(Opening(next, in: front.mailbox))
    }

    /// Undo took `change` back. The conversation it took the reader from, as the reader read it, to read again,
    /// unless the window has moved on since by any other way: then only its row comes back (R9).
    public mutating func undone(_ change: MailChange) -> Reader? {
        guard let departure, departure.change == change else { return nil }
        self.departure = nil
        return departure.left
    }

    private mutating func afterPick(_ change: MailChange, _ facts: Facts) -> Move {
        guard let front = facts.front, let anchor = front.pointerPick.first,
            Set(front.pointerPick).isSubset(of: change.threads), ReaderExit.exit(after: change.request) == .putAway
        else { return .stays }
        switch landing(after: change, from: anchor, trail: [], facts) {
        case .thread(let next):
            trail = Trail(thread: next, rows: front.rows)
            return .opens(Opening(next, in: front.mailbox))
        // Nothing is open to close: the rows leave, and the pick with them.
        case .list: return .stays
        }
    }

    private func landing(
        after change: MailChange, from anchor: ThreadSummary.ID, trail: [ThreadSummary.ID], _ facts: Facts
    ) -> Landing {
        Landing.after(
            putAway: Set(change.threads), anchor: anchor, trail: trail, rows: facts.front?.rows ?? [],
            setting: facts.setting)
    }
}
