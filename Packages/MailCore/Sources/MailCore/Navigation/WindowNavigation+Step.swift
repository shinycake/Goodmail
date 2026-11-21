/// Next and Previous Conversation (⌃⌘↓, ⌃⌘↑, and the reader's chevrons in a narrow window): the window reads the row
/// below or above the one read, in the list it was opened from, in every arrangement. Next is the row below in every
/// language. A conversation whose row has left since, as a read one leaves an Unread list, still steps from where its
/// row was, by the rows it was opened from.
extension WindowNavigation {
    /// Which way through the list.
    public enum Step: Equatable, Sendable {
        /// The row below.
        case next
        /// The row above.
        case previous

        /// The row this way from `anchor` in `place`, the rows top to bottom as they place it, that is still `listed`:
        /// the nearest below for Next, above for Previous. `nil` past the end, or when `place` doesn't hold `anchor`.
        func neighbor(
            of anchor: ThreadSummary.ID, in place: [ThreadSummary.ID], listed: Set<ThreadSummary.ID>
        ) -> ThreadSummary.ID? {
            guard let index = place.firstIndex(of: anchor) else { return nil }
            switch self {
            case .next: return place[place.index(after: index)...].first(where: listed.contains)
            case .previous: return place[..<index].last(where: listed.contains)
            }
        }
    }

    /// The conversation `step` reads from the list `front`, or `nil` when there is none: past either end, while
    /// several rows are picked with a pointer, in a message window, or with no list on show. With nothing read, Next
    /// reads the first row.
    public func conversation(_ step: Step, in front: Front?) -> ThreadSummary.ID? {
        guard state.layout == .viewer, let front, front.pointerPick.isEmpty else { return nil }
        let rows = front.rows
        guard let anchor = state.reading?.thread else { return step == .next ? rows.first : nil }
        // A row that left is placed by the rows it was opened from, unless that was another list's.
        let trail = opened.flatMap { $0.thread == anchor && $0.from == source ? $0.rows : nil } ?? []
        return step.neighbor(of: anchor, in: rows.contains(anchor) ? rows : trail, listed: Set(rows))
    }

    /// Reads the conversation `step` reaches in `front`, if there is one, in the place of the one read (R1). Undo's way
    /// back ends with it, as with any other move.
    mutating func take(_ step: Step, in front: Front?) {
        guard let front, let next = conversation(step, in: front) else { return }
        opened = Opened(thread: next, from: source, rows: front.rows, row: nil)
        state.read(Reading(next, in: front.mailbox))
    }
}
