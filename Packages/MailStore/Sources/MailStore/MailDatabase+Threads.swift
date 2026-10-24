import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// Inserts or updates the threads and replaces their labels. One short transaction (ADR-002).
    public func upsert(_ threads: [ThreadSummary]) throws {
        try write { db in
            for thread in threads { try Self.upsert(thread, in: db) }
        }
    }

    static func upsert(_ thread: ThreadSummary, generation: Int? = nil, in db: Database) throws {
        let accountID = thread.id.accountID.rawValue
        try ThreadRecord(thread).upsert(db)
        if let generation {
            try db.execute(
                sql: "UPDATE thread SET generation = ? WHERE accountID = ? AND id = ?",
                arguments: [generation, accountID, thread.id.threadID]
            )
        }
        try db.execute(
            sql: "DELETE FROM threadLabel WHERE accountID = ? AND threadID = ?",
            arguments: [accountID, thread.id.threadID]
        )
        for label in thread.labelIDs {
            try db.execute(
                sql: "INSERT INTO threadLabel (accountID, threadID, labelID) VALUES (?, ?, ?)",
                arguments: [accountID, thread.id.threadID, label]
            )
        }
    }

    /// The threads in `mailbox`, newest first. Emits now and after every change.
    public func threads(in mailbox: Mailbox) -> AsyncThrowingStream<[ThreadSummary], any Error> {
        // Signals from other processes re-run the query even when nothing it reads changed.
        observe { db in try Self.fetchThreads(db, in: mailbox) }
    }

    /// Follows a query on the main queue until the stream is dropped.
    func observe<Value: Equatable & Sendable>(_ fetch: @escaping @Sendable (Database) throws -> Value)
        -> AsyncThrowingStream<Value, any Error>
    {
        let observation = ValueObservation.tracking(fetch).removeDuplicates()
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

    public func thread(_ id: ThreadSummary.ID) throws -> ThreadSummary? {
        try pool.read { db in
            guard
                let record = try ThreadRecord.filter(
                    Column("accountID") == id.accountID.rawValue && Column("id") == id.threadID
                ).fetchOne(db)
            else { return nil }
            let labels = try String.fetchAll(
                db, sql: "SELECT labelID FROM threadLabel WHERE accountID = ? AND threadID = ?",
                arguments: [id.accountID.rawValue, id.threadID])
            return record.summary(labelIDs: Set(labels))
        }
    }

    /// `FROM … WHERE …` selecting the threads in `mailbox`.
    static func threadQuery(in mailbox: Mailbox) -> (sql: String, arguments: StatementArguments) {
        var sql: String
        var arguments: StatementArguments
        if let label = mailbox.labelID {
            sql = """
                FROM thread
                JOIN threadLabel ON threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                WHERE threadLabel.labelID = ?
                """
            arguments = [label]
        } else {
            sql = """
                FROM thread
                WHERE NOT EXISTS (
                    SELECT 1 FROM threadLabel AS excluded
                    WHERE excluded.accountID = thread.accountID AND excluded.threadID = thread.id
                    AND excluded.labelID IN (?, ?))
                """
            arguments = [SystemLabel.spam, SystemLabel.trash]
        }
        if let account = mailbox.accountID {
            sql += " AND thread.accountID = ?"
            arguments += [account.rawValue]
        }
        return (sql, arguments)
    }

    static func fetchThreads(_ db: Database, in mailbox: Mailbox) throws -> [ThreadSummary] {
        let query = threadQuery(in: mailbox)
        let rows = try Row.fetchCursor(
            db,
            sql: """
                SELECT thread.*,
                    (SELECT group_concat(labelID, char(31)) FROM threadLabel AS all_labels
                     WHERE all_labels.accountID = thread.accountID AND all_labels.threadID = thread.id) AS labelIDs
                """ + "\n" + query.sql + " ORDER BY thread.date DESC",
            arguments: query.arguments
        )
        return try Array(
            rows.map { row in
                let labels: String = row["labelIDs"] ?? ""
                return try ThreadRecord(row: row).summary(
                    labelIDs: Set(labels.split(separator: "\u{1F}").map(String.init)))
            }
        )
    }
}

struct ThreadRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "thread"

    var accountID: String
    var id: String
    var subject: String
    var snippet: String
    var senderName: String?
    var senderAddress: String
    var date: Date
    var isUnread: Bool
    var messageCount: Int

    init(_ thread: ThreadSummary) {
        accountID = thread.id.accountID.rawValue
        id = thread.id.threadID
        subject = thread.subject
        snippet = thread.snippet
        senderName = thread.sender.name
        senderAddress = thread.sender.address
        date = thread.date
        isUnread = thread.isUnread
        messageCount = thread.messageCount
    }

    var summaryID: ThreadSummary.ID {
        ThreadSummary.ID(accountID: AccountID(rawValue: accountID), threadID: id)
    }

    func summary(labelIDs: Set<String>) -> ThreadSummary {
        ThreadSummary(
            id: summaryID,
            subject: subject,
            snippet: snippet,
            sender: Contact(name: senderName, address: senderAddress),
            date: date,
            isUnread: isUnread,
            messageCount: messageCount,
            labelIDs: labelIDs
        )
    }
}
