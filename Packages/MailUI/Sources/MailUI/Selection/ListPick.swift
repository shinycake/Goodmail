import MailCore

/// What a list has picked, and for a conversation read, the rows as they were when it was picked, which place it once
/// its row leaves (`ListSelection.moving`). The trail goes with the pick, so it can't outlive the conversation it
/// was taken for: one picked while its row isn't listed has none.
nonisolated struct ListPick: Equatable, Sendable {
    private(set) var selection = ListSelection.none
    /// The rows when the conversation read was picked; empty unless it was listed then.
    private(set) var trail: [ThreadSummary.ID] = []

    /// The one transition: picks `new` among `rows`. The same pick again changes nothing, so a conversation read
    /// keeps its trail after its row leaves.
    mutating func pick(_ new: ListSelection, from rows: [ThreadSummary.ID]) {
        guard new != selection else { return }
        selection = new
        if case .reading(let id) = new, rows.contains(id) {
            trail = rows
        } else {
            trail = []
        }
    }
}
