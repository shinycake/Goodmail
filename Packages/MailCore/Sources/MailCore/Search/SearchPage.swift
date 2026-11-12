import Foundation

/// One page of the provider's matches for a search, across accounts, and where each account's next page starts.
public struct SearchPage: Equatable, Sendable {
    /// The matching threads, newest first within each account.
    public var ids: [ThreadSummary.ID]
    /// The next page token of each account with more matches.
    public var next: [AccountID: String]

    public init(ids: [ThreadSummary.ID] = [], next: [AccountID: String] = [:]) {
        self.ids = ids
        self.next = next
    }

    /// Whether some account has more matches.
    public var hasMore: Bool { !next.isEmpty }
}
