public import Foundation
public import GRDB
public import MailCore

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
        try replaceLabels(of: thread.id, with: thread.labelIDs, in: db)
    }

    public func thread(_ id: ThreadSummary.ID) throws -> ThreadSummary? {
        try read { db in try Self.thread(id, in: db) }
    }

    static func thread(_ id: ThreadSummary.ID, in db: Database) throws -> ThreadSummary? {
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
