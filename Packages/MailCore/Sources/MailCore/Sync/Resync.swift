public import Foundation

/// A resync filling the offline window page by page, saved with every page that lands.
public struct Resync: Codable, Equatable, Sendable {
    /// Taken before the first page, so changes made while resyncing are caught right after it.
    public var cursor: String
    public var startedAt: Date
    /// Stamped on every thread this resync stores; threads in the window without it are gone (see `Sweep`).
    public var generation: Int
    /// How many threads it has stored so far, for a scope that stops at a number (`SyncScope.inboxHead`).
    public private(set) var stored: Int
    public private(set) var position: Position

    /// How far the listing got. It saves the queries themselves, not their place in a list, so a resync resumed by
    /// a build that lists differently goes on with the queries it began, each page token with its own query.
    public enum Position: Codable, Equatable, Sendable {
        /// Nothing listed under a saved plan: just begun, or saved by a build that numbered its queries. Lists the
        /// scope's queries from the first.
        case unplanned
        /// Listing `query` from the page `pageToken` starts, its first when nil, then each of `next` in turn. The plan
        /// kept `sweeping` for as long as its long window, which the sweep then trusts.
        case listing(query: ThreadQuery, pageToken: String?, next: [ThreadQuery], sweeping: Set<String>)
        /// Every query listed; only the sweep of `sweeping`'s long window, and the rest's short one, is left.
        case listed(sweeping: Set<String>)
    }

    public init(
        cursor: String, startedAt: Date, generation: Int, position: Position = .unplanned, stored: Int = 0
    ) {
        self.cursor = cursor
        self.startedAt = startedAt
        self.generation = generation
        self.position = position
        self.stored = stored
    }

    /// What a resync lists, in order, and the labels whose long window it covers, which its sweep trusts.
    struct Plan: Equatable, Sendable {
        let queries: [ThreadQuery]
        let sweeping: Set<String>
    }

    /// Lists what `plan` says, unless a plan is under way already.
    mutating func plan(_ plan: Plan) {
        guard case .unplanned = position else { return }
        position = Self.listing(plan.queries[...], sweeping: plan.sweeping)
    }

    /// Notes that `page` of the query being listed landed. The query ends at its last page, or once the resync
    /// holds `limit` threads.
    mutating func record(_ page: ThreadPage, limit: Int) {
        guard case .listing(let query, _, let next, let sweeping) = position else { return }
        stored += page.threads.count
        if let token = page.nextPageToken, stored < limit {
            position = .listing(query: query, pageToken: token, next: next, sweeping: sweeping)
        } else {
            position = Self.listing(next[...], sweeping: sweeping)
        }
    }

    private static func listing(_ queries: ArraySlice<ThreadQuery>, sweeping: Set<String>) -> Position {
        guard let first = queries.first else { return .listed(sweeping: sweeping) }
        return .listing(query: first, pageToken: nil, next: Array(queries.dropFirst()), sweeping: sweeping)
    }

    private enum CodingKeys: String, CodingKey {
        case cursor, startedAt, generation, stored, position
    }

    /// A resync saved before `position` existed lists again from the first query, counting from nothing: its stage
    /// numbered queries this build may list differently, so neither the stage nor its page token can be trusted.
    /// The pages it already stored carry its generation, so listing them again only rewrites them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let position = try container.decodeIfPresent(Position.self, forKey: .position)
        self.init(
            cursor: try container.decode(String.self, forKey: .cursor),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            generation: try container.decode(Int.self, forKey: .generation),
            position: position ?? .unplanned,
            stored: position == nil ? 0 : try container.decode(Int.self, forKey: .stored))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(generation, forKey: .generation)
        try container.encode(stored, forKey: .stored)
        try container.encode(position, forKey: .position)
    }
}
