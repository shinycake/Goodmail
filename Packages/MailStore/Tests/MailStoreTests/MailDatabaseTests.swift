import Foundation
import GRDB
import Testing

@testable import MailStore

struct MailDatabaseTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "MailDatabaseTests-\(UUID().uuidString)")
        .appending(path: "mail.sqlite")

    @Test func opensInWALModeSoTheAppAndExtensionCanShareIt() throws {
        let database = try MailDatabase(url: url)
        let mode = try database.pool.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
    }

    @Test func appliesEveryMigration() throws {
        let database = try MailDatabase(url: url)
        let applied = try database.pool.read { db in try MailDatabase.migrator.appliedIdentifiers(db) }
        #expect(applied == Set(MailDatabase.migrator.migrations))
        #expect(try database.pool.read { db in try db.tableExists("account") })
    }

    @Test func reopeningAnExistingDatabaseIsHarmless() throws {
        _ = try MailDatabase(url: url)
        _ = try MailDatabase(url: url)
    }
}
