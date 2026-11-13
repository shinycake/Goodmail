import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

struct AccountStoreTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "AccountStoreTests-\(UUID().uuidString)")
        .appending(path: "mail.sqlite")

    @Test func anAccountKeepsItsService() throws {
        let database = try MailDatabase(url: url)
        let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
        try database.save(account)
        #expect(try database.accounts().map(\.service) == [.gmail])
    }

    @Test func accountsAddedBeforeServicesWereStoredAreGmail() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path)
        try MailDatabase.migrator.migrate(pool, upTo: "v13-cache-cap")
        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO account (id, email, color, createdAt) VALUES ('a1', 'me@example.com', 'teal', ?)",
                arguments: [Date.now])
        }
        try pool.close()

        #expect(try MailDatabase(url: url).accounts().map(\.service) == [.gmail])
    }

    @Test func anAccountOfAServiceThisBuildDoesNotKnowIsLeftOut() throws {
        let database = try MailDatabase(url: url)
        try database.save(
            Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail))
        try database.pool.write { db in try db.execute(sql: "UPDATE account SET service = 'pigeon'") }
        #expect(try database.accounts().isEmpty)
    }
}
