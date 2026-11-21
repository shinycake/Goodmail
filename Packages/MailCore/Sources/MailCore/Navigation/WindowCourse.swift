/// What one window shows, and where its reader goes after the reader asks a change of mail (`ReaderCourse`), held
/// together so nothing can change one without the other: every way the window moves, other than the course's own
/// landing, goes through `move(_:)` or `opened(_:from:)`, and either ends the way back Undo would take (R9). What the
/// window reads is recorded with the mailbox it reads in (`Reading`), so a rebuilt or restored reader is the same.
public struct WindowCourse: Sendable {
    /// What the window shows.
    public private(set) var shown: WindowState
    private var course = ReaderCourse()

    public init(showing shown: WindowState) {
        self.shown = shown
    }

    /// The window moved by any way but the course: another list, search, a pick of several, Back, a filter, Handoff
    /// or a rebuild for other accounts. Undo then brings back only the row.
    public mutating func move(_ change: (inout WindowState) -> Void) {
        change(&shown)
        course.navigated()
    }

    /// The window opened `reading` itself, by a tap, a click, an alert or a link, from a list showing `rows`.
    public mutating func opened(_ reading: Reading, from rows: [ThreadSummary.ID]) {
        shown.read(reading)
        course.opened(reading.thread, from: rows)
    }

    /// The reader asked `change` of some conversations: where the course takes the reader. The window then shows
    /// what it says and records it with `landed(on:)` or `landedOnList()`.
    public mutating func asked(_ change: MailChange, _ facts: ReaderCourse.Facts) -> ReaderCourse.Move {
        course.asked(change, facts)
    }

    /// The course's own move took the reader to `reading`, keeping Undo's way back.
    public mutating func landed(on reading: Reading) {
        shown.read(reading)
    }

    /// The course's own move took the reader back to the list, keeping Undo's way back.
    public mutating func landedOnList() {
        shown.closeReader()
    }

    /// Undo took `change` back: the conversation to read again, from a list now showing `rows`, if the window
    /// hasn't moved on since (R9). The window shows it and records it with `landed(on:)`.
    public mutating func undone(_ change: MailChange, rows: [ThreadSummary.ID]) -> ReaderCourse.Reader? {
        guard let left = course.undone(change) else { return nil }
        course.opened(left.thread, from: rows)
        return left
    }
}
