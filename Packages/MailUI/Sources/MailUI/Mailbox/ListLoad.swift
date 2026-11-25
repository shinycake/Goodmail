import MailCore

/// What fetches the threads below a list's end.
public enum OlderThreads {
    /// The provider's older pages, one at a time. Each fetch says whether more may come, which the list keeps.
    case pages(() async throws -> Bool)
    /// Pages whose owner knows whether there are more, as a search's, which start over as its text changes:
    /// `hasMore` says, so the list keeps nothing of its own about them.
    case owned(hasMore: () -> Bool, fetch: () async throws -> Void)
}

/// Whether the store has answered for what a list shows, with the threads the list shows meanwhile.
nonisolated enum Listing: Equatable, Sendable {
    /// Not yet, as just after a switch of category. The last category's threads stay shown until this one's come, so
    /// the switch is one change, but they say nothing of whether this one is empty.
    case waiting(showing: [ThreadSummary])
    /// With no threads at all so far, as Spam and Trash start while their first page is fetched.
    case empty
    /// With threads at some point, so an empty list now means they went. These are the latest.
    case listed([ThreadSummary])

    /// The threads the list shows.
    var threads: [ThreadSummary] {
        switch self {
        case .waiting(let threads), .listed(let threads): threads
        case .empty: []
        }
    }

    var hasAnswered: Bool {
        if case .waiting = self { return false }
        return true
    }

    /// After the store answers with `threads`.
    func answered(_ threads: [ThreadSummary]) -> Listing {
        if case .listed = self { return .listed(threads) }
        return threads.isEmpty ? .empty : .listed(threads)
    }

    /// Waiting for another answer, still showing what this one has.
    var waiting: Listing { .waiting(showing: threads) }
}

/// Where fetching older threads for the bottom of a list stands.
nonisolated enum OlderPages: Equatable, Sendable {
    case mayHaveMore
    /// A page is on its way, which another ask joins.
    case fetching(Task<Void, Never>)
    /// The provider has no more.
    case exhausted
}

/// What an empty list means, which decides what it shows in place of rows.
nonisolated enum EmptyListing: Equatable, Sendable {
    /// Nothing yet: the store hasn't answered.
    case unknown
    /// The store has listed nothing, and the first older page is on its way.
    case firstPage
    /// The store's threads went, and an older page is on its way, which may bring more.
    case emptiedWhilePaging
    /// The mailbox, or what the filter leaves of it, has nothing.
    case empty

    /// What an empty list means after `listing`, while `paging` says whether an older page that would show here is on
    /// its way.
    init(_ listing: Listing, paging: Bool) {
        switch (listing, paging) {
        case (.waiting, _): self = .unknown
        case (.empty, true): self = .firstPage
        case (.listed, true): self = .emptiedWhilePaging
        case (.empty, false), (.listed, false): self = .empty
        }
    }
}
