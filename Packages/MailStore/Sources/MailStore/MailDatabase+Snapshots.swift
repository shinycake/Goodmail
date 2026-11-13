import Foundation
import GRDB
import MailCore

/// One-shot reads for App Intents, Spotlight and widgets, which answer once instead of following the store.
extension MailDatabase {
    /// The newest `limit` threads in `mailbox`.
    public func threads(in mailbox: Mailbox, limit: Int) throws -> [ThreadSummary] {
        try pool.read { db in try Self.fetchThreads(db, query: Self.threadQuery(in: mailbox), limit: limit) }
    }

    /// The stored threads among `ids`, newest first, whatever mailbox they are in.
    public func threads(_ ids: [ThreadSummary.ID]) throws -> [ThreadSummary] {
        guard !ids.isEmpty else { return [] }
        // Thread IDs are only unique per account, so match the pair.
        let keys = ids.map { $0.accountID.rawValue + "\u{1F}" + $0.threadID }
        let query: (sql: String, arguments: StatementArguments) = (
            "FROM thread WHERE thread.accountID || char(31) || thread.id IN (SELECT value FROM json_each(?))",
            [String(decoding: try JSONEncoder().encode(keys), as: UTF8.self)]
        )
        return try pool.read { db in try Self.fetchThreads(db, query: query) }
    }

    /// The newest `limit` threads that search finds for `text` here, as the search screen's local matches.
    public func threads(matching text: String, limit: Int) throws -> [ThreadSummary] {
        guard let query = try Self.searchQuery(text, including: []) else { return [] }
        return try pool.read { db in try Self.fetchThreads(db, query: query, limit: limit) }
    }

    /// The thread's cached messages, oldest first; empty when none are.
    public func cachedMessages(inThread thread: ThreadSummary.ID) throws -> [Message] {
        let decoder = JSONDecoder()
        return try pool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT content FROM message WHERE accountID = ? AND threadID = ? ORDER BY date",
                arguments: [thread.accountID.rawValue, thread.threadID]
            )
            .map { try decoder.decode(Message.self, from: Data($0.utf8)) }
        }
    }
}
