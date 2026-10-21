import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// Inserts or updates the threads and replaces their labels. One short transaction (ADR-002).
    public func upsert(_ threads: [ThreadSummary]) throws {
        try pool.write { db in
            for thread in threads {
                try ThreadRecord(thread).upsert(db)
                try db.execute(
                    sql: "DELETE FROM threadLabel WHERE accountID = ? AND threadID = ?",
                    arguments: [thread.id.accountID.rawValue, thread.id.threadID]
                )
                for label in thread.labelIDs {
                    try db.execute(
                        sql: "INSERT INTO threadLabel (accountID, threadID, labelID) VALUES (?, ?, ?)",
                        arguments: [thread.id.accountID.rawValue, thread.id.threadID, label]
                    )
                }
            }
        }
    }

    /// Threads carrying `label` in every account, newest first. Emits now and after every change.
    public func threads(labeled label: String) -> AsyncThrowingStream<[ThreadSummary], any Error> {
        let observation = ValueObservation.tracking { db in try Self.fetchThreads(db, labeled: label) }
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

    static func fetchThreads(_ db: Database, labeled label: String) throws -> [ThreadSummary] {
        let rows = try Row.fetchCursor(
            db,
            sql: """
                SELECT thread.*,
                    (SELECT group_concat(labelID, char(31)) FROM threadLabel AS all_labels
                     WHERE all_labels.accountID = thread.accountID AND all_labels.threadID = thread.id) AS labelIDs
                FROM thread
                JOIN threadLabel ON threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                WHERE threadLabel.labelID = ?
                ORDER BY thread.date DESC
                """,
            arguments: [label]
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
