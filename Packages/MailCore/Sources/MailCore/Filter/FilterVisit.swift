/// A filtered list as one visit to it shows it, as Mail does: what the filter admits, and every conversation read here
/// since the filter or the list last changed, which stays listed while the filter does. A conversation read under
/// Unread so keeps its row once another opens, and Previous goes back to it.
public struct FilterVisit: Equatable, Sendable {
    /// What the list is filtered by.
    public private(set) var filter: ListFilter
    /// The conversations read during the visit, while the filter is on.
    private var readHere: Set<ThreadSummary.ID> = []

    public init(_ filter: ListFilter) {
        self.filter = filter
    }

    /// `thread` is read from the list.
    public mutating func read(_ thread: ThreadSummary.ID) {
        guard filter.isOn else { return }
        readHere.insert(thread)
    }

    /// The list is filtered by `new`: a different filter starts the visit over, keeping only the conversation
    /// `reading`, if one is, so it doesn't leave from under the reader.
    public mutating func filter(by new: ListFilter, reading: ThreadSummary.ID?) {
        guard new != filter else { return }
        filter = new
        restart(reading: reading)
    }

    /// The list shows something else, as another Inbox category: the visit starts over, keeping only the conversation
    /// `reading`, if one is.
    public mutating func restart(reading: ThreadSummary.ID?) {
        readHere = []
        if let reading { read(reading) }
    }

    /// Whether the list shows `thread`, which the filter `admits` or not: always while it is off, and always once it
    /// was read here.
    public func shows(_ thread: ThreadSummary.ID, admits: () -> Bool) -> Bool {
        !filter.isOn || readHere.contains(thread) || admits()
    }
}
