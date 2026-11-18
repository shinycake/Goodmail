public import MailCore

/// Writes each window's minimized messages in the order they were asked for, whatever order the writes arrive in. The
/// app starts each write at once, off the main actor, so the one made as it leaves the screen can't wait; two writes
/// started close together can then reach the store out of order, and a stale one must not replace a newer one.
public actor MinimizedDraftStore {
    private let database: MailDatabase
    /// The newest version written for each window.
    private var written: [String: Int] = [:]

    public init(database: MailDatabase) {
        self.database = database
    }

    /// The messages kept for `window` alone.
    public func drafts(of window: String) throws -> [Draft] {
        try database.minimizedDrafts(of: window)
    }

    /// The minimized messages of every window but those `open`, which now belong to `window`.
    public func claim(for window: String, sparing open: Set<String>) throws -> [Draft] {
        try database.claimMinimizedDrafts(for: window, sparing: open)
    }

    /// Makes `drafts` the minimized messages of `window`, unless a newer `version` was written already. Returns
    /// whether it wrote.
    @discardableResult
    public func keep(_ drafts: [Draft], for window: String, version: Int) throws -> Bool {
        guard version > written[window, default: Int.min] else { return false }
        try database.keepMinimizedDrafts(drafts, for: window)
        written[window] = version
        return true
    }
}
