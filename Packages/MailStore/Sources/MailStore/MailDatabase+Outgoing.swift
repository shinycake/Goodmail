import Foundation
import GRDB
import MailCore

/// A message's delivery is two columns: `failure` holds a failed message's reason and `upload` an uploading one's
/// attempt; a queued message has neither. Only `Delivery+Columns` below reads or writes them.
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
        try write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO outgoing (id, accountID, purpose, sendAt, failure, upload, draft)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: try Self.arguments(for: message))
        }
    }

    public func cancel(_ id: Draft.ID) throws -> OutgoingMessage? {
        try write { db in
            let queued = OutgoingMessage.Delivery.queued.condition
            guard
                let message = try Self.outgoing(
                    db, sql: "WHERE id = ? AND \(queued.sql)", arguments: [id.uuidString] + queued.arguments
                ).first
            else { return nil }
            try db.execute(sql: "DELETE FROM outgoing WHERE id = ?", arguments: [id.uuidString])
            return message
        }
    }

    public func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage? {
        try write { db in
            let queued = OutgoingMessage.Delivery.queued.condition
            try db.execute(
                sql: "UPDATE outgoing SET purpose = ?, sendAt = ? WHERE id = ? AND \(queued.sql)",
                arguments: [purpose.rawValue, date, id.uuidString] + queued.arguments)
            guard db.changesCount > 0 else { return nil }
            return try Self.outgoing(db, sql: "WHERE id = ?", arguments: [id.uuidString]).first
        }
    }

    public func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage] {
        let queued = OutgoingMessage.Delivery.queued.condition
        return try pool.read { db in
            try Self.outgoing(
                db, sql: "WHERE accountID = ? AND \(queued.sql) AND sendAt <= ? ORDER BY sendAt",
                arguments: [account.rawValue] + queued.arguments + [date])
        }
    }

    public func nextSendDate(for account: AccountID) throws -> Date? {
        let queued = OutgoingMessage.Delivery.queued.condition
        return try pool.read { db in
            try Date.fetchOne(
                db, sql: "SELECT MIN(sendAt) FROM outgoing WHERE accountID = ? AND \(queued.sql)",
                arguments: [account.rawValue] + queued.arguments)
        }
    }

    public func uploadingMessages(for account: AccountID) throws -> [OutgoingMessage] {
        try pool.read { db in
            try Self.outgoing(
                db, sql: "WHERE accountID = ? AND upload IS NOT NULL ORDER BY sendAt", arguments: [account.rawValue])
        }
    }

    public func update(_ id: Draft.ID, from expected: OutgoingMessage.Delivery, to message: OutgoingMessage?) throws
        -> Bool
    {
        let condition = expected.condition
        return try write { db in
            if let message {
                try db.execute(
                    sql: """
                        UPDATE outgoing SET id = ?, accountID = ?, purpose = ?, sendAt = ?, failure = ?, upload = ?,
                            draft = ?
                        WHERE id = ? AND \(condition.sql)
                        """,
                    arguments: try Self.arguments(for: message) + [id.uuidString] + condition.arguments)
            } else {
                try db.execute(
                    sql: "DELETE FROM outgoing WHERE id = ? AND \(condition.sql)",
                    arguments: [id.uuidString] + condition.arguments)
            }
            return db.changesCount > 0
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
                db, sql: "WHERE purpose = ? AND failure IS NULL AND upload IS NULL ORDER BY sendAt",
                arguments: [OutgoingMessage.Purpose.scheduledSend.rawValue])
        }
    }

    /// The earliest time a waiting message falls due, in any account.
    public func nextSendDate() throws -> Date? {
        try pool.read { db in
            try Date.fetchOne(db, sql: "SELECT MIN(sendAt) FROM outgoing WHERE failure IS NULL AND upload IS NULL")
        }
    }

    private static func arguments(for message: OutgoingMessage) throws -> StatementArguments {
        let draft = String(decoding: try JSONEncoder().encode(message.draft), as: UTF8.self)
        let columns = message.delivery.columns
        return [
            message.id.uuidString, message.draft.accountID.rawValue, message.purpose.rawValue, message.sendAt,
            columns.failure, columns.upload, draft,
        ]
    }

    private static func outgoing(_ db: Database, sql: String, arguments: StatementArguments) throws
        -> [OutgoingMessage]
    {
        let decoder = JSONDecoder()
        let rows = try Row.fetchAll(
            db, sql: "SELECT purpose, sendAt, failure, upload, draft FROM outgoing \(sql)", arguments: arguments)
        return try rows.map { row in
            let draft: String = row["draft"]
            // A purpose this build doesn't know is kept as a draft rather than sent.
            let purpose: String = row["purpose"]
            return OutgoingMessage(
                draft: try decoder.decode(Draft.self, from: Data(draft.utf8)),
                purpose: OutgoingMessage.Purpose(rawValue: purpose) ?? .saveDraft, sendAt: row["sendAt"],
                delivery: try OutgoingMessage.Delivery(failure: row["failure"], upload: row["upload"]))
        }
    }
}

/// The delivery's columns, and the condition that matches it.
extension OutgoingMessage.Delivery {
    struct CorruptRow: Error {}

    init(failure: String?, upload: String?) throws {
        switch (failure, upload) {
        case (nil, nil):
            self = .queued
        case (nil, let upload?):
            guard let id = UUID(uuidString: upload) else { throw CorruptRow() }
            self = .uploading(UploadID(rawValue: id))
        case (let failure?, nil):
            // A reason this build doesn't know is shown as a refusal.
            self = .failed(SendFailure(rawValue: failure) ?? .rejected)
        case (.some, .some):
            throw CorruptRow()
        }
    }

    var columns: (failure: String?, upload: String?) {
        switch self {
        case .queued: (nil, nil)
        case .uploading(let id): (nil, id.rawValue.uuidString)
        case .failed(let failure): (failure.rawValue, nil)
        }
    }

    var condition: (sql: String, arguments: StatementArguments) {
        switch self {
        case .queued: ("failure IS NULL AND upload IS NULL", [])
        case .uploading(let id): ("upload = ?", [id.rawValue.uuidString])
        case .failed(let failure): ("failure = ?", [failure.rawValue])
        }
    }
}
