import MailCore

/// How much of its mailbox a list reads from the store (ADR-045): its newest threads, more of them as the reader nears
/// their end, or every one while something needs them all. The view model holds one and changes it only through
/// `MailboxViewModel.moveWindow`, with the transitions here.
nonisolated struct ListWindow: Equatable, Sendable {
    /// What needs every thread listed, rather than the newest.
    enum Need: Hashable, Sendable {
        /// A filter, which shows what it admits of the whole mailbox.
        case filter
        /// Select All, while several stay picked.
        case selectAll
        /// Empty Trash, which deletes every thread in it.
        case everyThread
    }

    private enum State: Equatable, Sendable {
        /// The newest `count`, grown as the reader nears their end.
        case newest(Int)
        /// Every thread, while `needs`, never empty, hold it; then the newest `count` again, or more. `deepestRow` is
        /// the deepest row shown meanwhile, as the list placed it, so letting go can keep it (`letGo(_:keeping:)`).
        case whole(needs: Set<Need>, count: Int, deepestRow: Int?)
        /// Every thread, always: a list whose source has no window, as search's results.
        case unwindowed
    }

    private var state: State

    /// How close to the last row the list reads further, so the rows come before the reader gets there.
    static let lead = 20

    /// Twice as many: doubling bounds how often a deep scroll reads the mailbox again.
    private static func grown(_ count: Int) -> Int { count * 2 }

    /// A list of a mailbox read a window at a time, or with `windowed` false one its source lists whole. It starts on
    /// its first window, or whole for `needs`.
    init(windowed: Bool, needs: Set<Need> = []) {
        let count = ThreadWindow.firstCount
        switch (windowed, needs.isEmpty) {
        case (false, _): state = .unwindowed
        case (true, true): state = .newest(count)
        case (true, false): state = .whole(needs: needs, count: count, deepestRow: nil)
        }
    }

    /// What the list asks the store for now.
    var asked: ThreadWindow {
        switch state {
        case .newest(let count): .newest(count)
        case .whole, .unwindowed: .whole
        }
    }

    /// Whether the list reads every thread for `need` now, as it does always when it has no window.
    func isWhole(for need: Need) -> Bool {
        if case .unwindowed = state { return true }
        return holds(need)
    }

    /// Whether `need` holds the window whole, so letting it go may go back to the newest.
    func holds(_ need: Need) -> Bool {
        guard case .whole(let needs, _, _) = state else { return false }
        return needs.contains(need)
    }

    /// The deepest row shown while the list is whole, as the list placed it; `nil` while it isn't, or none was.
    var deepestRowShown: Int? {
        guard case .whole(_, _, let deepest) = state else { return nil }
        return deepest
    }

    /// The reader nears the end of the rows the store listed, which reach `reach`. Reads twice as many when the store
    /// holds more, and says whether it did; when it didn't, older threads can only come from the service.
    mutating func nearEnd(reach: ThreadListing.Reach) -> Bool {
        guard case .newest(let count) = state, reach == .more else { return false }
        state = .newest(Self.grown(count))
        return true
    }

    /// The reader was shown row `index` of the list, scrolling or reading. A whole list remembers the deepest.
    mutating func shown(row index: Int) {
        guard case .whole(let needs, let count, let deepest) = state, index > deepest ?? -1 else { return }
        state = .whole(needs: needs, count: count, deepestRow: index)
    }

    /// Reads every thread for `need`, until it is let go.
    mutating func hold(_ need: Need) {
        switch state {
        case .unwindowed:
            return
        case .newest(let count):
            state = .whole(needs: [need], count: count, deepestRow: nil)
        case .whole(var needs, let count, let deepest):
            needs.insert(need)
            state = .whole(needs: needs, count: count, deepestRow: deepest)
        }
    }

    /// Lets `need` go. Once nothing holds the list whole, it goes back to the newest threads: as many as before, or
    /// enough for the first `depth` of the store's order and the rows a scroll reaches next, so a reader who scrolled
    /// or read far down isn't left past the end.
    mutating func letGo(_ need: Need, keeping depth: Int) {
        guard case .whole(var needs, var count, let deepest) = state, needs.remove(need) != nil else { return }
        guard needs.isEmpty else {
            state = .whole(needs: needs, count: count, deepestRow: deepest)
            return
        }
        if depth > 0 {
            while count < depth + Self.lead { count = Self.grown(count) }
        }
        state = .newest(count)
    }

    /// Back to the first window, as for another category, whose rows start at the top. What needs every thread still
    /// does.
    mutating func restart() {
        let count = ThreadWindow.firstCount
        switch state {
        case .newest: state = .newest(count)
        case .whole(let needs, _, _): state = .whole(needs: needs, count: count, deepestRow: nil)
        case .unwindowed: return
        }
    }
}
