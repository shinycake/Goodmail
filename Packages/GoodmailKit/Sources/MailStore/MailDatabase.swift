import Foundation
import GRDB

/// The shared mail database. The app and the Notification Service Extension both write to it (ADR-002),
/// so every write is a short transaction and every process waits out the other's lock.
public final class MailDatabase: Sendable {
    let pool: DatabasePool

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
        pool = try DatabasePool(path: url.path, configuration: configuration)
        try Self.migrator.migrate(pool)
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
        return migrator
    }
}
