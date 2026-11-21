/// Where a window goes after the reader puts away the conversation they're reading (R7).
public enum Landing: Equatable, Sendable {
    /// The conversation to read next, from the same list.
    case thread(ThreadSummary.ID)
    /// The list, with nothing open.
    case list

    /// Where the window goes after `putAway` leave, read from the row `anchor`. `rows` is the list as it shows now,
    /// top to bottom, still holding what was put away; `trail` is the list as it showed when `anchor` opened, which
    /// places an anchor that has left since, as a read conversation leaves an Unread smart mailbox.
    ///
    /// Next is the first row below the anchor that stays, else the last above it. A conversation the list never
    /// held, as one opened from an alert, goes to the list.
    public static func after(
        putAway: Set<ThreadSummary.ID>, anchor: ThreadSummary.ID, trail: [ThreadSummary.ID],
        rows: [ThreadSummary.ID], setting: AfterRemoval
    ) -> Landing {
        guard setting == .next else { return .list }
        let place = rows.contains(anchor) ? rows : trail
        guard let index = place.firstIndex(of: anchor) else { return .list }
        let staying = Set(rows).subtracting(putAway)
        let next =
            place[place.index(after: index)...].first(where: staying.contains)
            ?? place[..<index].last(where: staying.contains)
        return next.map(Landing.thread) ?? .list
    }
}
