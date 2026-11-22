/// Where the reader goes when the reader asks a change of mail in the window, and only then (R6–R9): what sync,
/// other devices or other windows change only ever changes rows. Putting the conversation on show away goes on as
/// Settings says (`Landing`), and Undo brings the reader back to it while the window is still where the change left it.
extension WindowNavigation {
    /// The conversation on show, and how its reader sees it now.
    public struct Reader: Equatable, Sendable {
        /// Its row as the reader opened it, which Undo opens it again from without reading the store.
        public var summary: ThreadSummary
        /// Where it is read, which a label change can take it out of.
        public var mailbox: Mailbox
        /// Its labels before the change applies.
        public var labels: Set<String>

        public var thread: ThreadSummary.ID { summary.id }
        /// What the window reads while it is on show.
        public var reading: Reading { Reading(thread, in: mailbox) }

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
        /// Whether these are search's results over the list, rather than its own rows.
        public var searching: Bool

        public init(
            rows: [ThreadSummary.ID], pointerPick: [ThreadSummary.ID] = [], mailbox: Mailbox, searching: Bool = false
        ) {
            self.rows = rows
            self.pointerPick = pointerPick
            self.mailbox = mailbox
            self.searching = searching
        }
    }

    /// What the reader last left, by `change` (R9).
    struct Departure: Equatable, Sendable {
        let change: MailChange
        let target: Target

        /// What Undo of `change` brings the reader back to.
        enum Target: Equatable, Sendable {
            /// The conversation on show, and the list it was read in, which Undo reads it in again.
            case conversation(Reader, from: Opened.From)
            /// Several rows picked with a pointer, top to bottom, which Undo picks again while the list they were
            /// picked in is on show: the list's own rows, or search's over it.
            case pick([ThreadSummary.ID], from: Opened.From)
        }
    }

    /// The reader asked `change` of some conversations. Only a change to the conversation on show moves the reader;
    /// with none on show, putting away every row picked with a pointer reads the row after them, so Delete can be
    /// pressed again and again.
    mutating func asked(_ change: MailChange, reader: Reader?, front: Front?, in context: Context) -> [Effect] {
        departure = nil
        guard let reader else {
            afterPick(change, front: front, setting: context.afterRemoval)
            return []
        }
        guard change.threads.contains(reader.thread) else { return [] }
        let landing: Landing
        switch ReaderExit.exit(after: change.request, labels: reader.labels, readIn: reader.mailbox) {
        case .stays:
            return []
        // A message window keeps its own undo, in its place until the toast goes (ADR-035).
        case _ where state.layout == .message:
            return [.leaveWindow]
        case .setAside:
            landing = .list
        case .putAway:
            // The rows it was opened from, unless that was another list's.
            landing = Landing.after(
                putAway: Set(change.threads), anchor: reader.thread, trail: trail(of: reader.thread, in: front),
                rows: front?.rows ?? [],
                setting: context.afterRemoval)
        }
        let from = source(searching: front?.searching ?? false)
        land(on: landing, front: front)
        // After landing, whose change of state ends any way back before it.
        departure = Departure(change: change, target: .conversation(reader, from: from))
        return []
    }

    /// Undo took back `change`. The conversation it took the reader from opens again, as the reader read it, or the
    /// rows picked with a pointer are picked again, unless the window has moved on since by any other way: then only
    /// the rows come back (R9).
    mutating func undid(_ change: MailChange, rows: [ThreadSummary.ID], searching: Bool) -> [Effect] {
        guard let departure, departure.change == change else { return [] }
        self.departure = nil
        switch departure.target {
        case .conversation(let left, let from):
            opened = Opened(thread: left.thread, from: from, rows: rows, row: left.summary)
            state.read(left.reading)
            return []
        case .pick(let picked, let from):
            guard from == source(searching: searching) else { return [] }
            state.closeReader()
            return [.repick(picked)]
        }
    }

    /// Nothing open, every row picked with a pointer put away: the row after them opens. With nothing to go on to, the
    /// rows leave, and the pick with them. Either way Undo picks them again.
    private mutating func afterPick(_ change: MailChange, front: Front?, setting: AfterRemoval) {
        guard let front, let anchor = front.pointerPick.first, Set(front.pointerPick).isSubset(of: change.threads),
            ReaderExit.exit(after: change.request) == .putAway
        else { return }
        let landing = Landing.after(
            putAway: Set(change.threads), anchor: anchor, trail: [], rows: front.rows, setting: setting)
        if case .thread = landing { land(on: landing, front: front) }
        // After landing, whose change of state ends any way back before it.
        departure = Departure(
            change: change, target: .pick(front.pointerPick, from: source(searching: front.searching)))
    }

    /// The reader's own course went to `landing`, in the list `front`. The caller records the way back afterwards,
    /// since moving ends any before it.
    private mutating func land(on landing: Landing, front: Front?) {
        guard case .thread(let next) = landing, let front else {
            state.closeReader()
            return
        }
        opened = Opened(thread: next, from: source(searching: front.searching), rows: front.rows, row: nil)
        state.read(Reading(next, in: front.mailbox))
    }
}
