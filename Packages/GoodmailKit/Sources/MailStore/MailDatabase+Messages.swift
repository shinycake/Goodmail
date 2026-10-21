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
                        INSERT INTO message (accountID, id, threadID, date, content, fetchedAt)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        thread.accountID.rawValue, message.id.messageID, thread.threadID, message.date,
                        String(decoding: try encoder.encode(message), as: UTF8.self), fetchedAt,
                    ]
                )
            }
            // Fetched before queued actions reached the server: show them as the reader left them.
            try Self.reapplyPending(
                account: thread.accountID.rawValue, threadIDs: [thread.threadID], fetchedAt: fetchedAt, in: db)
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
