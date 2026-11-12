import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// Replaces the stored messages of `thread` with these. The thread must be stored. `fetchedAt` is when their
    /// fetch began.
    public func save(_ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date = .now) throws {
        let encoder = JSONEncoder()
        try write { db in
            try db.execute(
                sql: "DELETE FROM message WHERE accountID = ? AND threadID = ?",
                arguments: [thread.accountID.rawValue, thread.threadID]
            )
            for message in messages {
                try db.execute(
                    sql: """
                        INSERT INTO message (accountID, id, threadID, date, content, fetchedAt, bodyText)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        thread.accountID.rawValue, message.id.messageID, thread.threadID, message.date,
                        String(decoding: try encoder.encode(message), as: UTF8.self), fetchedAt,
                        Self.searchText(of: message.body),
                    ]
                )
            }
            // Fetched before queued actions reached the server: show them as the reader left them.
            try Self.reapplyPending(
                account: thread.accountID.rawValue, threadIDs: [thread.threadID], fetchedAt: fetchedAt, in: db)
        }
    }

    /// The words search finds a body by: its plain text, or else its HTML's text.
    static func searchText(of body: MessageBody) -> String {
        if let plain = body.plain, !plain.isEmpty { return plain }
        return body.html.map(HTMLEntities.plainText(fromHTML:)) ?? ""
    }

    /// Gives the bodies cached before search indexed them their text. Reads first, so an open with nothing to fill,
    /// the usual case, takes no write lock from the other process.
    static func fillMessageText(in pool: DatabasePool) throws {
        let missing = try pool.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM message WHERE bodyText IS NULL)") ?? false
        }
        guard missing else { return }
        let decoder = JSONDecoder()
        try pool.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT rowid, content FROM message WHERE bodyText IS NULL")
            for row in rows {
                let content: String = row["content"]
                // A body this build can't read is still searchable by its thread; give it no words.
                let message = try? decoder.decode(Message.self, from: Data(content.utf8))
                try db.execute(
                    sql: "UPDATE message SET bodyText = ? WHERE rowid = ?",
                    arguments: [message.map { searchText(of: $0.body) } ?? "", row["rowid"] as Int64])
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
