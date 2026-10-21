import Foundation
import GRDB
import MailCore

extension MailDatabase: SyncStore {
    public func syncState(for account: AccountID) throws -> SyncState? {
        try pool.read { db in
            guard
                let json = try String.fetchOne(
                    db, sql: "SELECT state FROM syncState WHERE accountID = ?", arguments: [account.rawValue])
            else { return nil }
            return try JSONDecoder().decode(SyncState.self, from: Data(json.utf8))
        }
    }

    public func apply(_ changes: StoreChanges) throws {
        let account = changes.accountID.rawValue
        try write { db in
            for thread in changes.upserts {
                try Self.upsert(thread, generation: changes.generation, in: db)
            }
            // A refetch may predate queued actions; keep showing them until they replay (ADR-008).
            try Self.reapplyPending(
                account: account, threadIDs: changes.upserts.map(\.id.threadID), fetchedAt: changes.fetchedAt, in: db)
            for id in changes.deletions {
                try db.execute(sql: "DELETE FROM thread WHERE accountID = ? AND id = ?", arguments: [account, id])
            }
            if let labels = changes.labels {
                try db.execute(sql: "DELETE FROM label WHERE accountID = ?", arguments: [account])
                for label in labels {
                    try LabelRecord(label, accountID: account).insert(db)
                }
            }
            if let sweep = changes.sweep {
                try Self.sweep(sweep, account: account, in: db)
            }
            if let state = changes.state {
                let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
                try db.execute(
                    sql: "INSERT OR REPLACE INTO syncState (accountID, state) VALUES (?, ?)",
                    arguments: [account, json]
                )
            }
        }
    }

    public func oldestThreadDate(labeled label: String, account: AccountID) throws -> Date? {
        try pool.read { db in
            try Date.fetchOne(
                db,
                sql: """
                    SELECT MIN(thread.date) FROM thread
                    JOIN threadLabel ON threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                    WHERE thread.accountID = ? AND threadLabel.labelID = ?
                    """,
                arguments: [account.rawValue, label]
            )
        }
    }

    /// The account's labels, system ones first, then by name.
    public func labels(for account: AccountID) throws -> [MailLabel] {
        try pool.read { db in
            try LabelRecord
                .filter(Column("accountID") == account.rawValue)
                .order(Column("kind"), Column("name"))
                .fetchAll(db)
                .map(\.label)
        }
    }

    private static func sweep(_ sweep: Sweep, account: String, in db: Database) throws {
        let labels = sweep.longWindowLabels.sorted()
        let placeholders = databaseQuestionMarks(count: labels.count)
        var arguments: StatementArguments = [account, sweep.generation, sweep.allMailSince, sweep.longWindowSince]
        arguments += StatementArguments(labels)
        try db.execute(
            sql: """
                DELETE FROM thread
                WHERE accountID = ? AND generation < ? AND (
                    date >= ? OR (date >= ? AND EXISTS (
                        SELECT 1 FROM threadLabel
                        WHERE threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                        AND threadLabel.labelID IN (\(placeholders))
                    ))
                )
                """,
            arguments: arguments
        )
    }
}

struct LabelRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "label"

    var accountID: String
    var id: String
    var name: String
    var kind: String
    var color: String?
    var isHidden: Bool

    init(_ label: MailLabel, accountID: String) {
        self.accountID = accountID
        id = label.id
        name = label.name
        kind = label.kind.rawValue
        color = label.color
        isHidden = label.isHidden
    }

    var label: MailLabel {
        MailLabel(id: id, name: name, kind: MailLabel.Kind(rawValue: kind) ?? .user, color: color, isHidden: isHidden)
    }
}
