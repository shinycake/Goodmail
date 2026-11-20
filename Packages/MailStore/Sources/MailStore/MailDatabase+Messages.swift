public import Foundation
import GRDB
public import MailCore

extension MailDatabase {
    /// Replaces the stored messages of `thread` with these. The thread must be stored. `fetchedAt` is when their
    /// fetch began; `accessedAt` is when the reader last wanted them, which the cache cap evicts by.
    public func save(
        _ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date = .now, accessedAt: Date = .now
    ) throws {
        try write { db in
            try Self.replace(messages, inThread: thread, fetchedAt: fetchedAt, accessedAt: accessedAt, in: db)
        }
    }

    /// Like `save`, for messages fetched for a thread the store may not list yet, as when an alert opens one before
    /// the sync that brings it: they're kept only when it does. Returns whether they were.
    @discardableResult
    public func saveIfListed(
        _ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date = .now, accessedAt: Date = .now
    ) throws -> Bool {
        try write { db in
            guard try Self.thread(thread, in: db) != nil else { return false }
            try Self.replace(messages, inThread: thread, fetchedAt: fetchedAt, accessedAt: accessedAt, in: db)
            return true
        }
    }

    private static func replace(
        _ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date, accessedAt: Date, in db: Database
    ) throws {
        let encoder = JSONEncoder()
        try db.execute(
            sql: "DELETE FROM message WHERE accountID = ? AND threadID = ?",
            arguments: [thread.accountID.rawValue, thread.threadID]
        )
        for message in messages {
            let content = String(decoding: try encoder.encode(message), as: UTF8.self)
            let text = message.body.text
            try db.execute(
                sql: """
                    INSERT INTO message (accountID, id, threadID, date, content, fetchedAt, bodyText, size, accessedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    thread.accountID.rawValue, message.id.messageID, thread.threadID, message.date,
                    content, fetchedAt, text, content.utf8.count + text.utf8.count, accessedAt,
                ]
            )
        }
        // Fetched before queued actions reached the server: show them as the reader left them.
        try reapplyPending(
            account: thread.accountID.rawValue, threadIDs: [thread.threadID], fetchedAt: fetchedAt, in: db)
    }

    /// Gives the bodies cached before search indexed them their text. Reads first, so an open with nothing to fill,
    /// the usual case, takes no write lock from the other process.
    ///
    /// `batch` bodies at a time, each batch its own short write: the notification extension can be the first to open
    /// the database after an update, inside its small memory limit, and the other process waits out every write.
    static func fillMessageText(in pool: DatabasePool, batch: Int = 200) throws {
        let missing = try pool.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM message WHERE bodyText IS NULL)") ?? false
        }
        guard missing else { return }
        let decoder = JSONDecoder()
        var filled = batch
        while filled == batch {
            filled = try pool.write { db in
                let rows = try Row.fetchAll(
                    db, sql: "SELECT rowid, content FROM message WHERE bodyText IS NULL LIMIT ?", arguments: [batch])
                for row in rows {
                    let content: String = row["content"]
                    // A body this build can't read is still searchable by its thread; give it no words.
                    let message = try? decoder.decode(Message.self, from: Data(content.utf8))
                    let text = message.map { $0.body.text } ?? ""
                    try db.execute(
                        sql: "UPDATE message SET bodyText = ?, size = size + ? WHERE rowid = ?",
                        arguments: [text, text.utf8.count, row["rowid"] as Int64])
                }
                return rows.count
            }
        }
    }

    /// The thread's stored messages, oldest first. Emits now (empty if none are cached) and after every change.
    public func messages(inThread thread: ThreadSummary.ID) -> AsyncThrowingStream<[Message], any Error> {
        let observation = ValueObservation.tracking { db in
            let decoder = JSONDecoder()
            return try String.fetchAll(
                db,
                sql: "SELECT content FROM message WHERE accountID = ? AND threadID = ? ORDER BY date",
                arguments: [thread.accountID.rawValue, thread.threadID]
            )
            .map { try decoder.decode(Message.self, from: Data($0.utf8)) }
        }
        .removeDuplicates()
        return AsyncThrowingStream { continuation in
            let cancellable = observation.start(
                in: pool,
                scheduling: .async(onQueue: .main),
                onError: { continuation.finish(throwing: $0) },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
