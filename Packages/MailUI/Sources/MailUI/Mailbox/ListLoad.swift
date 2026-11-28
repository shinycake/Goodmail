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
    /// Not yet, as just after a switch of category or window. The last answer's threads stay shown until this one's
    /// come, so the switch is one change, but they say nothing of whether this one is empty.
    case waiting(showing: ThreadListing)
    /// With no threads at all so far, as Spam and Trash start while their first page is fetched.
    case empty
    /// With threads at some point, so an empty list now means they went. These are the latest.
    case listed(ThreadListing)

    /// What the list shows.
    var shown: ThreadListing {
        switch self {
        case .waiting(let listing), .listed(let listing): listing
        case .empty: ThreadListing(whole: [])
        }
    }

    /// The threads in the window the list shows.
    var threads: [ThreadSummary] { shown.threads }

    /// The pinned and woken threads the store held below the window.
    var held: [ThreadSummary] { shown.held }

    /// Whether the store's answer reaches the end of the mailbox; `nil` until it answers.
    var reach: ThreadListing.Reach? {
        switch self {
        case .waiting: nil
        case .empty: .whole
        case .listed(let listing): listing.reach
        }
    }

    var hasAnswered: Bool {
        if case .waiting = self { return false }
        return true
    }

    /// After the store answers with `listing`.
    func answered(_ listing: ThreadListing) -> Listing {
        if case .listed = self { return .listed(listing) }
        return listing.threads.isEmpty ? .empty : .listed(listing)
    }

    /// Waiting for another answer, still showing what this one has.
    var waiting: Listing { .waiting(showing: shown) }
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
