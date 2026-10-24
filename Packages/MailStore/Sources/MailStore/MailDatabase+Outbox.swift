import Foundation
import GRDB
import MailCore

extension MailDatabase: OutboxStore {
    public func enqueue(_ intents: [OutboxIntent], account: AccountID) throws -> [String: Set<String>] {
        try write { db in
            var before: [String: Set<String>] = [:]
            for intent in intents {
                guard
                    let labels = try Self.apply(
                        intent.action, account: account.rawValue, thread: intent.threadID, in: db)
                else { continue }
                before[intent.threadID] = before[intent.threadID] ?? labels
                try db.execute(
                    sql: "INSERT INTO outbox (id, accountID, threadID, intent) VALUES (?, ?, ?, ?)",
                    arguments: [
                        intent.id.uuidString, account.rawValue, intent.threadID,
                        String(decoding: try JSONEncoder().encode(intent), as: UTF8.self),
                    ]
                )
            }
            return before
        }
    }

    public func pendingIntents(for account: AccountID) throws -> [OutboxIntent] {
        try pool.read { db in
            try Self.intents(account: account.rawValue, unsentOnly: true, threadIDs: nil, in: db)
        }
    }

    public func markSent(_ id: OutboxIntent.ID, at date: Date) throws {
        try write { db in
            try db.execute(sql: "UPDATE outbox SET sentAt = ? WHERE id = ?", arguments: [date, id.uuidString])
        }
    }

    public func removeIntent(_ id: OutboxIntent.ID) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM outbox WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// After a fetch rewrote these threads, re-applies the intents it can't show yet: unsent ones, and ones sent
    /// after it began. Intents sent before it began are in what it fetched, so they're done with. Without
    /// `fetchedAt`, every intent is re-applied.
    static func reapplyPending(account: String, threadIDs: [String], fetchedAt: Date?, in db: Database) throws {
        guard !threadIDs.isEmpty else { return }
        if let fetchedAt {
            try db.execute(
                sql: """
                    DELETE FROM outbox WHERE accountID = ? AND sentAt <= ?
                    AND threadID IN (\(databaseQuestionMarks(count: threadIDs.count)))
                    """,
                arguments: [account, fetchedAt] + StatementArguments(threadIDs))
        }
        for intent in try intents(account: account, unsentOnly: false, threadIDs: threadIDs, in: db) {
            _ = try apply(intent.action, account: account, thread: intent.threadID, in: db)
        }
    }

    private static func intents(account: String, unsentOnly: Bool, threadIDs: [String]?, in db: Database) throws
        -> [OutboxIntent]
    {
        var sql = "SELECT intent FROM outbox WHERE accountID = ?"
        var arguments: StatementArguments = [account]
        if unsentOnly { sql += " AND sentAt IS NULL" }
        if let threadIDs {
            sql += " AND threadID IN (\(databaseQuestionMarks(count: threadIDs.count)))"
            arguments += StatementArguments(threadIDs)
        }
        let decoder = JSONDecoder()
        return try String.fetchAll(db, sql: sql + " ORDER BY sequence", arguments: arguments)
            .map { try decoder.decode(OutboxIntent.self, from: Data($0.utf8)) }
    }

    /// Applies `action` to a stored thread's labels and its cached messages. Returns the thread's labels from
    /// before, or `nil` when the thread isn't stored.
    private static func apply(_ action: ThreadAction, account: String, thread: String, in db: Database) throws
        -> Set<String>?
    {
        // Summaries keep unread as a flag, not a label; actions see it as Gmail's UNREAD label.
        guard
            let isUnread = try Bool.fetchOne(
                db, sql: "SELECT isUnread FROM thread WHERE accountID = ? AND id = ?", arguments: [account, thread])
        else { return nil }
        var before = Set(
            try String.fetchAll(
                db, sql: "SELECT labelID FROM threadLabel WHERE accountID = ? AND threadID = ?",
                arguments: [account, thread]))
        if isUnread { before.insert(SystemLabel.unread) }
        let after = action.applied(to: before)
        if after != before {
            try db.execute(
                sql: "DELETE FROM threadLabel WHERE accountID = ? AND threadID = ?", arguments: [account, thread])
            for label in after.subtracting([SystemLabel.unread]) {
                try db.execute(
                    sql: "INSERT INTO threadLabel (accountID, threadID, labelID) VALUES (?, ?, ?)",
                    arguments: [account, thread, label])
            }
            try db.execute(
                sql: "UPDATE thread SET isUnread = ? WHERE accountID = ? AND id = ?",
                arguments: [after.contains(SystemLabel.unread), account, thread])
        }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let rows = try Row.fetchAll(
            db, sql: "SELECT id, content FROM message WHERE accountID = ? AND threadID = ?",
            arguments: [account, thread])
        for row in rows {
            let content: String = row["content"]
            var message = try decoder.decode(Message.self, from: Data(content.utf8))
            let labels = action.applied(to: message.labelIDs)
            guard labels != message.labelIDs else { continue }
            message.labelIDs = labels
            try db.execute(
                sql: "UPDATE message SET content = ? WHERE accountID = ? AND id = ?",
                arguments: [String(decoding: try encoder.encode(message), as: UTF8.self), account, row["id"] as String])
        }
        return before
    }
}
