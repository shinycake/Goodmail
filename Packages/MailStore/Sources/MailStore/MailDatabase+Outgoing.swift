import Foundation
import GRDB
import MailCore

extension MailDatabase: OutgoingStore {
    public func enqueue(_ message: OutgoingMessage) throws {
        let draft = String(decoding: try JSONEncoder().encode(message.draft), as: UTF8.self)
        try write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO outgoing (id, accountID, purpose, sendAt, failure, draft)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    message.id.uuidString, message.draft.accountID.rawValue, message.purpose.rawValue, message.sendAt,
                    message.failure, draft,
                ])
        }
    }

    public func cancel(_ id: Draft.ID) throws -> OutgoingMessage? {
        try write { db in
            guard let message = try Self.outgoing(db, sql: "WHERE id = ?", arguments: [id.uuidString]).first
            else { return nil }
            try db.execute(sql: "DELETE FROM outgoing WHERE id = ?", arguments: [id.uuidString])
            return message
        }
    }

    public func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage] {
        try pool.read { db in
            try Self.outgoing(
                db, sql: "WHERE accountID = ? AND failure IS NULL AND sendAt <= ? ORDER BY sendAt",
                arguments: [account.rawValue, date])
        }
    }

    public func nextSendDate(for account: AccountID) throws -> Date? {
        try pool.read { db in
            try Date.fetchOne(
                db, sql: "SELECT MIN(sendAt) FROM outgoing WHERE accountID = ? AND failure IS NULL",
                arguments: [account.rawValue])
        }
    }

    public func markFailed(_ id: Draft.ID, reason: String) throws {
        try write { db in
            try db.execute(sql: "UPDATE outgoing SET failure = ? WHERE id = ?", arguments: [reason, id.uuidString])
        }
    }

    public func remove(_ id: Draft.ID) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM outgoing WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Messages that failed to send, in every account. Emits now and after every change.
    public func failedMessages() -> AsyncThrowingStream<[OutgoingMessage], any Error> {
        let observation = ValueObservation.tracking { db in
            try Self.outgoing(db, sql: "WHERE failure IS NOT NULL ORDER BY sendAt", arguments: [])
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

    private static func outgoing(_ db: Database, sql: String, arguments: StatementArguments) throws
        -> [OutgoingMessage]
    {
        let decoder = JSONDecoder()
        let rows = try Row.fetchAll(
            db, sql: "SELECT purpose, sendAt, failure, draft FROM outgoing \(sql)", arguments: arguments)
        return try rows.map { row in
            let draft: String = row["draft"]
            // A purpose this build doesn't know is kept as a draft rather than sent.
            let purpose: String = row["purpose"]
            return OutgoingMessage(
                draft: try decoder.decode(Draft.self, from: Data(draft.utf8)),
                purpose: OutgoingMessage.Purpose(rawValue: purpose) ?? .saveDraft, sendAt: row["sendAt"],
                failure: row["failure"])
        }
    }
}
