/// What a mailbox list has picked. On touch the list either reads one thread or is in Select mode; with a pointer the
/// two merge, so one picked row is the open conversation and several are what the toolbar and menus act on.
///
/// The transitions are pure: each takes the list's rows, top to bottom, and returns the next value. The pointer ones
/// never leave `several` holding one row or none, which reads that row or nothing instead. Select mode on touch may
/// hold any number, since it stays on until Done.
public enum ListSelection: Hashable, Sendable {
    case none
    /// One conversation, shown in the reader.
    case reading(ThreadSummary.ID)
    /// Several, chosen in Select mode on touch or with ⌘ and ⇧ on a desktop. The reader shows how many. `anchor` is
    /// the row ⇧ extends from and Escape goes back to: the last one clicked on its own or with ⌘.
    case several(Set<ThreadSummary.ID>, anchor: ThreadSummary.ID?)

    /// How a click picks a row.
    public enum Click: Sendable {
        /// Reads the row alone.
        case plain
        /// ⌘: adds the row, or takes it away.
        case toggle
        /// ⇧: picks every row from the anchor to this one.
        case extend
    }

    /// Every picked row.
    public var ids: Set<ThreadSummary.ID> {
        switch self {
        case .none: []
        case .reading(let id): [id]
        case .several(let ids, _): ids
        }
    }

    /// The picked rows in the order of `rows`, leaving out any not among them.
    public func ids(in rows: [ThreadSummary.ID]) -> [ThreadSummary.ID] {
        let ids = ids
        return rows.filter(ids.contains)
    }

    /// The row ⇧ extends from: the one being read, or the anchor of several.
    private var anchor: ThreadSummary.ID? {
        switch self {
        case .none: nil
        case .reading(let id): id
        case .several(_, let anchor): anchor
        }
    }

    // MARK: Pointer and keys

    /// After a click on `row`.
    public func clicking(_ row: ThreadSummary.ID, _ click: Click, in rows: [ThreadSummary.ID]) -> ListSelection {
        switch click {
        case .plain:
            return .reading(row)
        case .toggle:
            var ids = ids
            guard ids.remove(row) == nil else {
                return .picked(ids, anchor: anchor.flatMap { ids.contains($0) ? $0 : nil })
            }
            ids.insert(row)
            return .picked(ids, anchor: row)
        case .extend:
            guard let anchor, let range = Self.range(from: anchor, to: row, in: rows) else { return .reading(row) }
            return .picked(Set(range), anchor: anchor)
        }
    }

    /// After ↓ (`offset` 1) or ↑ (-1), with ⇧ when `extending`. Stops at either end of the list.
    public func moving(_ offset: Int, extending: Bool, in rows: [ThreadSummary.ID]) -> ListSelection {
        let indices = ids(in: rows).compactMap(rows.firstIndex(of:))
        guard let top = indices.min(), let bottom = indices.max() else {
            return rows.first.map(ListSelection.reading) ?? .none
        }
        func clamped(_ index: Int) -> Int { min(max(index, 0), rows.count - 1) }
        guard extending, let anchor, let anchorIndex = rows.firstIndex(of: anchor) else {
            // Plain arrows leave several from their edge in the direction of travel.
            return .reading(rows[clamped((offset > 0 ? bottom : top) + offset)])
        }
        // The moving end is the one away from the anchor; with the anchor alone or inside, the one ahead.
        let head: Int
        switch (anchorIndex == top, anchorIndex == bottom) {
        case (true, false): head = bottom
        case (false, true): head = top
        default: head = offset > 0 ? bottom : top
        }
        let moved = clamped(head + offset)
        return .picked(Set(rows[min(anchorIndex, moved)...max(anchorIndex, moved)]), anchor: anchor)
    }

    /// After Select All: every row, keeping the anchor.
    public func selectingAll(in rows: [ThreadSummary.ID]) -> ListSelection {
        .picked(Set(rows), anchor: anchor.flatMap { rows.contains($0) ? $0 : nil } ?? rows.first)
    }

    /// After Escape: several drop back to the anchor alone.
    public var dropped: ListSelection {
        guard case .several(_, let anchor) = self else { return self }
        return anchor.map(ListSelection.reading) ?? .none
    }

    /// What a menu opened on `row` acts on: the whole pick when the row is in it, otherwise that row alone.
    public func acting(on row: ThreadSummary.ID) -> Set<ThreadSummary.ID> {
        let ids = ids
        return ids.contains(row) ? ids : [row]
    }

    // MARK: Rows leaving

    /// After the list went from `old` to `new` rows, with a pointer: picked rows that left are dropped, and when none
    /// is left the row after the first that left is read, or the one before when they were last, so Delete can be
    /// pressed again and again. Rows that were never listed, as a thread opened from a notification, stay picked.
    public func following(removalFrom old: [ThreadSummary.ID], to new: [ThreadSummary.ID]) -> ListSelection {
        let present = Set(new)
        let listed = Set(old)
        let ids = ids
        let gone = ids.filter { listed.contains($0) && !present.contains($0) }
        guard !gone.isEmpty else { return self }
        let kept = ids.subtracting(gone)
        guard kept.isEmpty else { return .picked(kept, anchor: anchor.flatMap { kept.contains($0) ? $0 : nil }) }
        guard let start = old.firstIndex(where: gone.contains) else { return .none }
        let next = old[start...].first(where: present.contains) ?? old[..<start].last(where: present.contains)
        return next.map(ListSelection.reading) ?? .none
    }

    /// After the list's rows became `rows`, on touch: rows that left are dropped and nothing else moves. Select mode
    /// stays on however few are left.
    public func keeping(_ rows: [ThreadSummary.ID]) -> ListSelection {
        let present = Set(rows)
        switch self {
        case .none:
            return .none
        case .reading(let id):
            return present.contains(id) ? self : .none
        case .several(let ids, let anchor):
            return .several(ids.intersection(present), anchor: anchor.flatMap { present.contains($0) ? $0 : nil })
        }
    }

    // MARK: Helpers

    /// A pointer's pick of `ids`: one is read, none is nothing.
    private static func picked(_ ids: Set<ThreadSummary.ID>, anchor: ThreadSummary.ID?) -> ListSelection {
        guard ids.count > 1 else { return ids.first.map(ListSelection.reading) ?? .none }
        return .several(ids, anchor: anchor)
    }

    /// The rows from `start` to `end`, whichever way round, or `nil` when either isn't listed.
    private static func range(from start: ThreadSummary.ID, to end: ThreadSummary.ID, in rows: [ThreadSummary.ID])
        -> ArraySlice<ThreadSummary.ID>?
    {
        guard let from = rows.firstIndex(of: start), let to = rows.firstIndex(of: end) else { return nil }
        return rows[min(from, to)...max(from, to)]
    }
}
