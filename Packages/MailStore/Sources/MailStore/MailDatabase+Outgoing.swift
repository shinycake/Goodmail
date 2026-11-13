import Foundation
import GRDB
import MailCore

extension MailDatabase: OutgoingStore {
    /// An account that isn't on the device, as after it was removed.
    public struct AccountMissing: Error, Equatable {
        public let account: AccountID
    }

    public func sender(for account: AccountID) throws -> Contact {
        let record = try pool.read { db in try AccountRecord.fetchOne(db, key: account.rawValue) }
        guard let record else { throw AccountMissing(account: account) }
        return Contact(name: record.name, address: record.email)
    }

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
                    message.failure?.rawValue, draft,
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

    public func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage? {
        try write { db in
            try db.execute(
                sql: "UPDATE outgoing SET purpose = ?, sendAt = ? WHERE id = ? AND failure IS NULL",
                arguments: [purpose.rawValue, date, id.uuidString])
            guard db.changesCount > 0 else { return nil }
            return try Self.outgoing(db, sql: "WHERE id = ?", arguments: [id.uuidString]).first
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

    public func markFailed(_ id: Draft.ID, reason: SendFailure) throws {
        try write { db in
            try db.execute(
                sql: "UPDATE outgoing SET failure = ? WHERE id = ?", arguments: [reason.rawValue, id.uuidString])
        }
    }

    public func remove(_ id: Draft.ID) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM outgoing WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Messages that failed to send, in every account. Emits now and after every change.
    public func failedMessages() -> AsyncThrowingStream<[OutgoingMessage], any Error> {
        observe { db in try Self.outgoing(db, sql: "WHERE failure IS NOT NULL ORDER BY sendAt", arguments: []) }
    }

    /// Messages waiting for the time the writer picked, in every account, soonest first. Emits now and after every
    /// change.
    public func scheduledMessages() -> AsyncThrowingStream<[OutgoingMessage], any Error> {
        observe { db in
            try Self.outgoing(
                db, sql: "WHERE purpose = ? AND failure IS NULL ORDER BY sendAt",
                arguments: [OutgoingMessage.Purpose.scheduledSend.rawValue])
        }
    }

    /// The earliest time a waiting message falls due, in any account.
    public func nextSendDate() throws -> Date? {
        try pool.read { db in
            try Date.fetchOne(db, sql: "SELECT MIN(sendAt) FROM outgoing WHERE failure IS NULL")
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
            // A failure this build doesn't know, such as the English sentences earlier builds stored, still failed.
            let failure: String? = row["failure"]
            return OutgoingMessage(
                draft: try decoder.decode(Draft.self, from: Data(draft.utf8)),
                purpose: OutgoingMessage.Purpose(rawValue: purpose) ?? .saveDraft, sendAt: row["sendAt"],
                failure: failure.map { SendFailure(rawValue: $0) ?? .rejected })
        }
    }
}
