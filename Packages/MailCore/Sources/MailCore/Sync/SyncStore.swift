public import Foundation

/// Where an account's sync stands. Saved in the same transaction as the mail it describes, so a crash
/// resumes from the last page that landed and never skips one.
public enum SyncState: Codable, Equatable, Sendable {
    /// Filling the offline window from scratch: the first sync, or after the cursor expired.
    case resyncing(Resync)
    /// Up to date as of `cursor`; the next sync asks for changes since it.
    case current(cursor: String)
}

public struct Resync: Codable, Equatable, Sendable {
    /// Taken before the first page, so changes made while resyncing are caught right after it.
    public var cursor: String
    public var startedAt: Date
    /// Stamped on every thread this resync stores; threads in the window without it are gone (see `Sweep`).
    public var generation: Int
    public var stage: Int
    public var pageToken: String?
    /// How many threads it has stored so far, for a scope that stops at a number (`SyncScope.inboxHead`).
    public var stored: Int

    public init(
        cursor: String, startedAt: Date, generation: Int, stage: Int = 0, pageToken: String? = nil, stored: Int = 0
    ) {
        self.cursor = cursor
        self.startedAt = startedAt
        self.generation = generation
        self.stage = stage
        self.pageToken = pageToken
        self.stored = stored
    }

    private enum CodingKeys: String, CodingKey {
        case cursor, startedAt, generation, stage, pageToken, stored
    }

    /// A resync saved before `stored` existed counts from nothing, which only a scope that stops at a number reads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cursor: try container.decode(String.self, forKey: .cursor),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            generation: try container.decode(Int.self, forKey: .generation),
            stage: try container.decode(Int.self, forKey: .stage),
            pageToken: try container.decodeIfPresent(String.self, forKey: .pageToken),
            stored: try container.decodeIfPresent(Int.self, forKey: .stored) ?? 0)
    }
}

/// Removes an account's threads that a finished resync covered but didn't see: deleted, or moved out of the
/// window, while the cursor was expired. Threads outside the window are older mail fetched by backfill.
public struct Sweep: Equatable, Sendable {
    public var generation: Int
    /// Every thread from this date on was listed.
    public var allMailSince: Date
    /// Threads with one of `longWindowLabels` from this date on were listed too.
    public var longWindowSince: Date
    public var longWindowLabels: Set<String>

    public init(generation: Int, allMailSince: Date, longWindowSince: Date, longWindowLabels: Set<String>) {
        self.generation = generation
        self.allMailSince = allMailSince
        self.longWindowSince = longWindowSince
        self.longWindowLabels = longWindowLabels
    }
}

/// One atomic write for one account. Every field is optional work; `state` lands with the mail it covers.
public struct StoreChanges: Sendable {
    public var accountID: AccountID
    public var upserts: [ThreadSummary] = []
    public var deletions: [String] = []
    /// Replaces the account's labels.
    public var labels: [MailLabel]?
    /// Replaces the account's signature; empty clears it.
    public var signature: String?
    /// Replaces the account's aliases, the other addresses it sends as.
    public var aliases: [Contact]?
    /// Replaces the account's address book.
    public var addressBook: AddressBook?
    /// Stamped on `upserts` during a resync.
    public var generation: Int?
    public var sweep: Sweep?
    public var state: SyncState?
    /// When the fetch that produced `upserts` began. Actions sent after it aren't in them yet (ADR-008).
    public var fetchedAt: Date?

    public init(
        accountID: AccountID,
        upserts: [ThreadSummary] = [],
        deletions: [String] = [],
        labels: [MailLabel]? = nil,
        signature: String? = nil,
        aliases: [Contact]? = nil,
        addressBook: AddressBook? = nil,
        generation: Int? = nil,
        sweep: Sweep? = nil,
        state: SyncState? = nil,
        fetchedAt: Date? = nil
    ) {
        self.accountID = accountID
        self.upserts = upserts
        self.deletions = deletions
        self.labels = labels
        self.signature = signature
        self.aliases = aliases
        self.addressBook = addressBook
        self.generation = generation
        self.sweep = sweep
        self.state = state
        self.fetchedAt = fetchedAt
    }
}

/// The people an account keeps contacts for, as fetched at one time.
public struct AddressBook: Equatable, Sendable {
    public var contacts: [Contact]
    /// The profile photos the service keeps for some of `contacts`, by lowercased address.
    public var photos: [String: URL]
    public var fetchedAt: Date

    public init(contacts: [Contact], photos: [String: URL] = [:], fetchedAt: Date) {
        self.contacts = contacts
        self.photos = photos
        self.fetchedAt = fetchedAt
    }
}

/// The persistence the sync engine needs. `MailStore` implements it; tests use memory.
public protocol SyncStore: Sendable {
    func syncState(for account: AccountID) throws -> SyncState?
    /// Applies everything in one transaction, or nothing.
    func apply(_ changes: StoreChanges) throws
    /// The date of the account's oldest stored thread in `mailbox`, where backfill continues from.
    func oldestThreadDate(in mailbox: Mailbox, account: AccountID) throws -> Date?
    /// When the account's address book was last fetched, if ever.
    func addressBookDate(for account: AccountID) throws -> Date?
    /// The account's labels, as the last sync stored them.
    func labels(for account: AccountID) throws -> [MailLabel]
    /// The account's stored threads that carry any of `labels`.
    func threadIDs(labeled labels: Set<String>, account: AccountID) throws -> [String]
}
