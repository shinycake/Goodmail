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
    }

    /// The conversation `step` reads from the list `front`, or `nil` when there is none: past either end, while
    /// several rows are picked with a pointer, in a message window, or with no list on show. With nothing read, Next
    /// reads the first row.
    public func conversation(_ step: Step, in front: Front?) -> ThreadSummary.ID? {
        guard state.layout == .viewer, let front, front.pointerPick.isEmpty else { return nil }
        let rows = front.rows
        guard let anchor = state.reading?.thread else { return step == .next ? rows.first : nil }
        if let index = rows.firstIndex(of: anchor) {
            let target = step == .next ? rows.index(after: index) : index - 1
            return rows.indices.contains(target) ? rows[target] : nil
        }
        // Its row left: where it was among the rows it was opened from, to the nearest that is still listed.
        guard let opened, opened.thread == anchor, opened.from == source,
            let index = opened.rows.firstIndex(of: anchor)
        else { return nil }
        let listed = Set(rows)
        switch step {
        case .next: return opened.rows[opened.rows.index(after: index)...].first(where: listed.contains)
        case .previous: return opened.rows[..<index].last(where: listed.contains)
        }
    }

    /// Reads the conversation `step` reaches in `front`, if there is one, in the place of the one read (R1). Undo's way
    /// back ends with it, as with any other move.
    mutating func take(_ step: Step, in front: Front?) {
        guard let front, let next = conversation(step, in: front) else { return }
        opened = Opened(thread: next, from: source, rows: front.rows, row: nil)
        state.read(Reading(next, in: front.mailbox))
        departure = nil
    }
}
