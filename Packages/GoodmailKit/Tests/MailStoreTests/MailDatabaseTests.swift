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

    /// Offline search (ADR-007) depends on FTS5 being compiled in.
    @Test func supportsFTS5() throws {
        let database = try MailDatabase(url: url)
        try database.pool.write { db in
            try db.create(virtualTable: "probe", using: FTS5()) { $0.column("body") }
            try db.execute(sql: "INSERT INTO probe(body) VALUES ('שלום עולם hello world')")
        }
        let hits = try database.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM probe WHERE probe MATCH 'שלום'")
        }
        #expect(hits == 1)
    }
}
