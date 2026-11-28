public import Foundation

/// Where an account's sync stands. Saved in the same transaction as the mail it describes, so a crash
/// resumes from the last page that landed and never skips one.
public enum SyncState: Codable, Equatable, Sendable {
    /// Filling the offline window from scratch: the first sync, or after the cursor expired.
    case resyncing(Resync)
    /// Up to date as of `cursor`; the next sync asks for changes since it.
    case current(cursor: String)
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

/// Where a write takes an account's sync, landing in the same transaction as the mail it covers.
public enum SyncProgress: Sendable {
    /// A page of a resync landed: its threads carry the resync's generation, and the resync goes on from here.
    case resyncing(Resync)
    /// The resync listed everything: `sweep` drops what it didn't see, and the account is current as of `cursor`.
    case resynced(Sweep, cursor: String)
    /// Up to date as of `cursor`; the next sync asks for changes since it.
    case current(cursor: String)

    /// The sync state saved with the write.
    public var state: SyncState {
        switch self {
        case .resyncing(let resync): .resyncing(resync)
        case .resynced(_, let cursor), .current(let cursor): .current(cursor: cursor)
        }
    }
}

/// One atomic write for one account. Every field is optional work; `progress` lands with the mail it covers.
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
    public var progress: SyncProgress?
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
        progress: SyncProgress? = nil,
        fetchedAt: Date? = nil
    ) {
        self.accountID = accountID
        self.upserts = upserts
        self.deletions = deletions
        self.labels = labels
        self.signature = signature
        self.aliases = aliases
        self.addressBook = addressBook
        self.progress = progress
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
    /// Stores the account's signature, empty for none. Returns the revision of the stored accounts the write left,
    /// read in its transaction, for the app to wait until it shows (ADR-043).
    func storeSignature(_ signature: String, for account: AccountID) throws -> Int
    /// The date of the account's oldest stored thread in `mailbox`, where backfill continues from.
    func oldestThreadDate(in mailbox: Mailbox, account: AccountID) throws -> Date?
    /// When the account's address book was last fetched, if ever.
    func addressBookDate(for account: AccountID) throws -> Date?
    /// The account's labels, as the last sync stored them.
    func labels(for account: AccountID) throws -> [MailLabel]
    /// The account's stored threads that carry any of `labels`.
    func threadIDs(labeled labels: Set<String>, account: AccountID) throws -> [String]
}
