import Foundation

/// Which thread each of an account's messages belongs to, for providers whose changes name messages rather than
/// threads: IMAP reports an expunged message by its UID, and Graph's delta a removed one by its message ID. The
/// provider records messages as it fetches them, then looks up the threads of the ones that changed.
///
/// It is a lookup cache, not mail: an entry may outlive its thread in the store, and losing it only costs a refetch.
public protocol MessageIndexStore: Sendable {
    /// Adds the entries, replacing any with the same key.
    func record(_ entries: [MessageIndexEntry], account: AccountID) throws
    /// The entries with these keys. Keys never recorded are left out.
    func indexEntries(withKeys keys: [String], account: AccountID) throws -> [MessageIndexEntry]
    /// Every entry in these threads.
    func indexEntries(inThreads threadIDs: [String], account: AccountID) throws -> [MessageIndexEntry]
    /// The entries for messages with these RFC 5322 Message-IDs, which IMAP threads on.
    func indexEntries(withInternetMessageIDs ids: [String], account: AccountID) throws -> [MessageIndexEntry]
    /// Removes the entries with these keys. Keys never recorded are ignored.
    func forgetIndexEntries(withKeys keys: [String], account: AccountID) throws
}

public struct MessageIndexEntry: Hashable, Sendable {
    /// The provider's key for the message, such as Graph's message ID.
    public var key: String
    public var threadID: String
    /// The RFC 5322 `Message-ID`, for a provider that threads on it.
    public var internetMessageID: String?

    public init(key: String, threadID: String, internetMessageID: String? = nil) {
        self.key = key
        self.threadID = threadID
        self.internetMessageID = internetMessageID
    }
}
