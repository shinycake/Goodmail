import AppIntents
import CoreSpotlight
import MailCore

/// Keeps Spotlight's copy of the newest conversations current. Indexed entities are the one way into Spotlight
/// (ADR-012): a found conversation opens through `OpenThreadIntent`.
public struct SpotlightIndexer: Sendable {
    let host: any MailIntentsHost
    let index: any SpotlightIndex

    public init(host: any MailIntentsHost) {
        self.init(host: host, index: SystemSpotlightIndex())
    }

    init(host: any MailIntentsHost, index: any SpotlightIndex) {
        self.host = host
        self.index = index
    }

    /// How many of the newest conversations Spotlight holds, and how far back it looks for ones to take out.
    static let window = 500

    /// Indexes the newest conversations, and takes out the newest ones moved to Spam or Trash since. Reads the
    /// database, so it runs off the caller's actor.
    @concurrent public func refresh() async throws {
        let change = try Catalog(host: host).spotlightChange(window: Self.window)
        try await index.index(change.index)
        try await index.remove(change.remove)
    }

    /// Empties Spotlight's copy and indexes the newest conversations again, as after an account is removed.
    @concurrent public func rebuild() async throws {
        try await index.removeAll()
        try await refresh()
    }
}

/// Where conversations are indexed: Spotlight, or a record of the calls in tests.
protocol SpotlightIndex: Sendable {
    func index(_ threads: [ThreadEntity]) async throws
    func remove(_ identifiers: [String]) async throws
    func removeAll() async throws
}

/// The system's Spotlight index.
struct SystemSpotlightIndex: SpotlightIndex {
    func index(_ threads: [ThreadEntity]) async throws {
        guard !threads.isEmpty else { return }
        try await CSSearchableIndex.default().indexAppEntities(threads)
    }

    func remove(_ identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await CSSearchableIndex.default().deleteAppEntities(identifiedBy: identifiers, ofType: ThreadEntity.self)
    }

    func removeAll() async throws {
        try await CSSearchableIndex.default().deleteAppEntities(ofType: ThreadEntity.self)
    }
}

extension Catalog {
    /// What Spotlight should hold: the newest `window` conversations outside Spam and Trash, without their
    /// messages, and the newest in Spam and Trash to take out.
    func spotlightChange(window: Int) throws -> (index: [ThreadEntity], remove: [String]) {
        let current = try host.threads(in: .allMail, limit: window).map { ThreadEntity($0, messages: []) }
        let gone = try [Mailbox.spam, .trash].flatMap { try host.threads(in: $0, limit: window) }
        return (current, gone.map { EntityID.string($0.id) })
    }
}
