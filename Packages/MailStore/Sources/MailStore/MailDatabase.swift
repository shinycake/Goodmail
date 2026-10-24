import Foundation
import GRDB

/// The shared mail database. The app and the Notification Service Extension both write to it (ADR-002),
/// so every write is a short transaction and every process waits out the other's lock.
public final class MailDatabase: Sendable {
    let pool: DatabasePool
    private let signal: ChangeSignal

    /// Opens (creating if needed) the database at `url` and migrates it to the current schema.
    public init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The NSE opens the database while the phone is locked; files created here inherit this class.
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        try Self.migrator.migrate(pool)
        self.pool = pool
        // Another process wrote: re-run this process's observations against the new data.
        signal = ChangeSignal {
            try? pool.write { db in try db.notifyChanges(in: .fullDatabase) }
        }
    }

    /// Every write goes through here, so the other processes hear about it.
    func write<T>(_ updates: (Database) throws -> T) throws -> T {
        let result = try pool.write(updates)
        signal.post()
        return result
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-accounts") { db in
            try db.create(table: "account") { table in
                table.primaryKey("id", .text)
                table.column("email", .text).notNull().unique()
                table.column("color", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2-threads") { db in
            try db.create(table: "thread") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("id", .text).notNull()
                table.column("subject", .text).notNull()
                table.column("snippet", .text).notNull()
                table.column("senderName", .text)
                table.column("senderAddress", .text).notNull()
                table.column("date", .datetime).notNull()
                table.column("isUnread", .boolean).notNull()
                table.column("messageCount", .integer).notNull()
                table.primaryKey(["accountID", "id"])
            }
            // Gmail labels are many-to-many; folder providers will map each folder to one label row.
            try db.create(table: "threadLabel") { table in
                table.column("accountID", .text).notNull()
                table.column("threadID", .text).notNull()
                table.column("labelID", .text).notNull()
                table.primaryKey(["accountID", "threadID", "labelID"])
                table.foreignKey(["accountID", "threadID"], references: "thread", onDelete: .cascade)
            }
            try db.create(index: "threadLabel_byLabel", on: "threadLabel", columns: ["labelID", "accountID"])
            try db.create(index: "thread_byDate", on: "thread", columns: ["date"])
        }
        migrator.registerMigration("v3-sync") { db in
            // The resync that last saw the thread; see `Sweep`.
            try db.alter(table: "thread") { table in
                table.add(column: "generation", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "label") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("id", .text).notNull()
                table.column("name", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("color", .text)
                table.column("isHidden", .boolean).notNull()
                table.primaryKey(["accountID", "id"])
            }
            try db.create(table: "syncState") { table in
                table.primaryKey("accountID", .text).references("account", onDelete: .cascade)
                table.column("state", .jsonText).notNull()
            }
        }
        migrator.registerMigration("v4-messages") { db in
            // Bodies are cached per thread and go with it (ADR-007).
            try db.create(table: "message") { table in
                table.column("accountID", .text).notNull()
                table.column("id", .text).notNull()
                table.column("threadID", .text).notNull()
                table.column("date", .datetime).notNull()
                table.column("content", .jsonText).notNull()
                table.column("fetchedAt", .datetime).notNull()
                table.primaryKey(["accountID", "id"])
                table.foreignKey(["accountID", "threadID"], references: "thread", onDelete: .cascade)
            }
            try db.create(index: "message_byThread", on: "message", columns: ["accountID", "threadID", "date"])
        }
        migrator.registerMigration("v5-outbox") { db in
            // Not tied to the thread: an intent outlives a sweep that removes its thread, and is dropped on replay.
            try db.create(table: "outbox") { table in
                table.autoIncrementedPrimaryKey("sequence")
                table.column("id", .text).notNull().unique()
                table.column("accountID", .text).notNull()
                table.column("threadID", .text).notNull()
                table.column("intent", .jsonText).notNull()
            }
            try db.create(index: "outbox_byThread", on: "outbox", columns: ["accountID", "threadID"])
        }
        migrator.registerMigration("v6-outbox-sent") { db in
            try db.alter(table: "outbox") { table in
                table.add(column: "sentAt", .datetime)
            }
        }
        migrator.registerMigration("v7-outgoing") { db in
            try db.create(table: "outgoing") { table in
                table.column("id", .text).primaryKey()
                table.column("accountID", .text).notNull()
                table.column("sendAt", .datetime).notNull()
                table.column("failure", .text)
                table.column("draft", .jsonText).notNull()
            }
        }
        migrator.registerMigration("v8-search") { db in
            // Kept in step with `thread` by triggers. Bodies aren't indexed: most mail is never opened here.
            try db.create(virtualTable: "threadSearch", using: FTS5()) { table in
                table.synchronize(withTable: "thread")
                table.tokenizer = .unicode61()
                table.column("subject")
                table.column("senderName")
                table.column("senderAddress")
                table.column("snippet")
            }
        }
        migrator.registerMigration("v9-signature") { db in
            try db.alter(table: "account") { table in table.add(column: "signature", .text) }
        }
        migrator.registerMigration("v10-outgoing-purpose") { db in
            try db.alter(table: "outgoing") { table in
                table.add(column: "purpose", .text).notNull().defaults(to: "send")
            }
        }
        migrator.registerMigration("v11-address-book") { db in
            try db.create(table: "addressBook") { table in
                table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                table.column("address", .text).notNull().collate(.nocase)
                table.column("name", .text)
                table.column("fetchedAt", .datetime).notNull()
                table.primaryKey(["accountID", "address"])
            }
        }
        return migrator
    }
}
