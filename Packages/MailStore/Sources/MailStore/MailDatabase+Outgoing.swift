public import Foundation
import GRDB
public import MailCore

#if canImport(os)
    import os
#endif

/// A message's delivery is two columns: `failure` holds a failed message's reason and `upload` an uploading one's
/// attempt; a queued message has neither, and no message has both (`v37-delivery-checks`). Only the `Delivery`
/// extension below reads or writes them, or says what matches them.
extension MailDatabase: OutgoingStore {
    /// An account that isn't on the device, as after it was removed.
    public struct AccountMissing: Error, Equatable {
        public let account: AccountID
    }

    public func sender(for account: AccountID) throws -> Contact {
        let record = try read { db in try AccountRecord.fetchOne(db, key: account.rawValue) }
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

    public func enqueueSave(_ message: OutgoingMessage) throws {
        let queued = OutgoingMessage.Delivery.queued.condition
        try write { db in
            try db.execute(
                sql: """
                    INSERT INTO outgoing (id, accountID, purpose, sendAt, failure, upload, draft)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET draft = excluded.draft, sendAt = MIN(sendAt, excluded.sendAt)
                    WHERE purpose = excluded.purpose AND \(queued.sql)
                    """,
                arguments: try Self.arguments(for: message) + queued.arguments)
        }
    }

    public func finish(_ message: OutgoingMessage) throws -> Bool {
        let queued = OutgoingMessage.Delivery.queued.condition
        let draft = try Self.encoded(message.draft)
        return try write { db in
            try db.execute(
                sql: "DELETE FROM outgoing WHERE id = ? AND draft = ? AND \(queued.sql)",
                arguments: [message.id.uuidString, draft] + queued.arguments)
            return db.changesCount > 0
        }
    }

    public func savedCopy(of draft: Draft.ID) throws -> Message.ID? {
        try read { db in
            try Row.fetchOne(
                db, sql: "SELECT accountID, messageID FROM savedDraftCopy WHERE draftID = ?",
                arguments: [draft.uuidString]
            ).map { Message.ID(accountID: AccountID(rawValue: $0["accountID"]), messageID: $0["messageID"]) }
        }
    }

    public func setSavedCopy(_ copy: Message.ID?, of draft: Draft.ID) throws {
        try write { db in
            if let copy {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO savedDraftCopy (draftID, accountID, messageID) VALUES (?, ?, ?)",
                    arguments: [draft.uuidString, copy.accountID.rawValue, copy.messageID])
            } else {
                try db.execute(sql: "DELETE FROM savedDraftCopy WHERE draftID = ?", arguments: [draft.uuidString])
            }
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
        return try read { db in
            try Self.readableOutgoing(
                db, sql: "WHERE accountID = ? AND \(queued.sql) AND sendAt <= ? ORDER BY sendAt",
                arguments: [account.rawValue] + queued.arguments + [date])
        }
    }

    public func uploadingMessages(for account: AccountID) throws -> [OutgoingMessage] {
        try read { db in
            try Self.readableOutgoing(
                db,
                sql: "WHERE accountID = ? AND \(OutgoingMessage.Delivery.Stage.uploading.condition) ORDER BY sendAt",
                arguments: [account.rawValue])
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

    /// The earliest time a waiting message falls due, in any account. Skips rows that don't read, as the queue
    /// does, so nothing asks to wake for one; it reads the rows soonest first and stops at the first that reads.
    public func nextSendDate() throws -> Date? {
        try read { db in
            let queued = try Row.fetchCursor(
                db,
                sql: """
                    SELECT purpose, sendAt, failure, upload, draft FROM outgoing
                    WHERE \(OutgoingMessage.Delivery.Stage.queued.condition) ORDER BY sendAt
                    """)
            while let row = try queued.next() {
                if let message = Self.readable(row) { return message.sendAt }
            }
            return nil
        }
    }

    /// The draft column. The same draft encodes the same, which `finish` relies on to tell a newer save apart.
    private static func encoded(_ draft: Draft) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(draft), as: UTF8.self)
    }

    private static func arguments(for message: OutgoingMessage) throws -> StatementArguments {
        let draft = try encoded(message.draft)
        let columns = message.delivery.columns
        return [
            message.id.uuidString, message.draft.accountID.rawValue, message.purpose.rawValue, message.sendAt,
            columns.failure, columns.upload, draft,
        ]
    }

    /// The messages the rows hold, or an error for the first that doesn't read, so a write that reads one back
    /// rolls back rather than report it gone.
    private static func outgoing(_ db: Database, sql: String, arguments: StatementArguments) throws
        -> [OutgoingMessage]
    {
        try rows(db, sql: sql, arguments: arguments).map { try message(in: $0) }
    }

    /// The messages the rows hold, for the lists and the queue. A row that doesn't read is left out and logged, so
    /// the rest of its account's queue still goes, and stays where it is for a build that reads it.
    fileprivate static func readableOutgoing(_ db: Database, sql: String, arguments: StatementArguments) throws
        -> [OutgoingMessage]
    {
        try rows(db, sql: sql, arguments: arguments).compactMap(readable)
    }

    /// The message `row` holds, or `nil`, logged, when it doesn't read.
    private static func readable(_ row: Row) -> OutgoingMessage? {
        do {
            return try message(in: row)
        } catch {
            #if canImport(os)
                Logger(subsystem: "com.idanbirman.goodmail", category: "outgoing")
                    .error("An outgoing message didn't read and was left out: \(error, privacy: .private)")
            #endif
            return nil
        }
    }

    private static func rows(_ db: Database, sql: String, arguments: StatementArguments) throws -> [Row] {
        try Row.fetchAll(
            db, sql: "SELECT purpose, sendAt, failure, upload, draft FROM outgoing \(sql)", arguments: arguments)
    }

    private static func message(in row: Row) throws -> OutgoingMessage {
        let draft: String = row["draft"]
        // A purpose this build doesn't know is kept as a draft rather than sent.
        let purpose: String = row["purpose"]
        return OutgoingMessage(
            draft: try JSONDecoder().decode(Draft.self, from: Data(draft.utf8)),
            purpose: OutgoingMessage.Purpose(rawValue: purpose) ?? .saveDraft, sendAt: row["sendAt"],
            delivery: try OutgoingMessage.Delivery(failure: row["failure"], upload: row["upload"]))
    }
}

extension MailFollowing {
    /// Messages that failed to send, in every account. Emits now and after every change.
    public func failedMessages() -> AsyncThrowingStream<[OutgoingMessage], any Error> {
        followed.observe { db in
            try MailDatabase.readableOutgoing(
                db, sql: "WHERE \(OutgoingMessage.Delivery.Stage.failed.condition) ORDER BY sendAt", arguments: [])
        }
    }

    /// Messages waiting for the time the writer picked, in every account, soonest first. Emits now and after every
    /// change.
    public func scheduledMessages() -> AsyncThrowingStream<[OutgoingMessage], any Error> {
        followed.observe { db in
            try MailDatabase.readableOutgoing(
                db, sql: "WHERE purpose = ? AND \(OutgoingMessage.Delivery.Stage.queued.condition) ORDER BY sendAt",
                arguments: [OutgoingMessage.Purpose.scheduledSend.rawValue])
        }
    }

    /// Everything queued to go in one conversation, whatever its purpose and however far it got, in the order it
    /// goes. The thread lives inside each draft, so the account's queue, a handful of rows, is read and filtered.
    /// Emits now and after every change.
    public func outgoingMessages(inThread thread: ThreadSummary.ID) -> AsyncThrowingStream<[OutgoingMessage], any Error>
    {
        followed.observe { db in
            try MailDatabase.readableOutgoing(
                db, sql: "WHERE accountID = ? ORDER BY sendAt", arguments: [thread.accountID.rawValue]
            )
            .filter { $0.draft.threadID == thread.threadID }
        }
    }
}

/// The delivery's columns, and the conditions that match them.
extension OutgoingMessage.Delivery {
    struct CorruptRow: Error {}

    /// Each kind of delivery, whatever its upload or failure.
    enum Stage {
        case queued, uploading, failed

        /// Matches every message of this kind.
        var condition: String {
            switch self {
            case .queued: "failure IS NULL AND upload IS NULL"
            case .uploading: "upload IS NOT NULL"
            case .failed: "failure IS NOT NULL"
            }
        }
    }

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

    /// Matches this delivery alone.
    var condition: (sql: String, arguments: StatementArguments) {
        switch self {
        case .queued: (Stage.queued.condition, [])
        case .uploading(let id): ("upload = ?", [id.rawValue.uuidString])
        case .failed(let failure): ("failure = ?", [failure.rawValue])
        }
    }
}
