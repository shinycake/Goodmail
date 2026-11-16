import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

struct AccountStoreTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "AccountStoreTests-\(UUID().uuidString)")
        .appending(path: "mail.sqlite")
    private let home = Account(
        id: AccountID(rawValue: "home"), email: "home@example.com", color: .teal, service: .gmail)
    private let work = Account(
        id: AccountID(rawValue: "work"), email: "work@example.com", color: .orange, service: .gmail)

    @Test func anAccountKeepsItsService() throws {
        let database = try MailDatabase(url: url)
        try database.save(home)
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
        try database.save(home)
        try database.pool.write { db in try db.execute(sql: "UPDATE account SET service = 'pigeon'") }
        #expect(try database.accounts().isEmpty)
    }

    @Test func aNewAccountHasNoNameUntilOneIsGiven() throws {
        let database = try MailDatabase(url: url)
        try database.save(home)
        try database.save(work)
        #expect(try database.accounts().map(\.name) == [nil, nil])
    }

    @Test func updatingAnAccountKeepsItsPlaceAndItsMail() throws {
        let database = try MailDatabase(url: url)
        try database.save(home)
        try database.save(work)
        try database.upsert([
            ThreadSummary(
                id: ThreadSummary.ID(accountID: home.id, threadID: "t1"), subject: "Hi", snippet: "",
                sender: Contact(name: nil, address: "a@example.com"), date: .now,
                isUnread: true, messageCount: 1, labelIDs: ["INBOX"])
        ])
        var renamed = home
        renamed.name = "Idan Birman"
        renamed.color = .purple
        try database.update(renamed)

        #expect(try database.accounts() == [renamed, work])
        #expect(try database.thread(ThreadSummary.ID(accountID: home.id, threadID: "t1")) != nil)
    }

    private let school = Account(
        id: AccountID(rawValue: "school"), email: "school@example.com", color: .purple, service: .icloud)

    @Test func accountsKeepTheOrderTheReaderGivesThem() throws {
        let database = try MailDatabase(url: url)
        for account in [home, work, school] { try database.save(account) }
        try database.reorderAccounts([school.id, home.id, work.id])
        #expect(try database.accounts() == [school, home, work])
        #expect(try MailDatabase(url: url).accounts() == [school, home, work])
    }

    @Test func anAccountAddedAfterReorderingGoesLast() throws {
        let database = try MailDatabase(url: url)
        try database.save(home)
        try database.save(work)
        try database.reorderAccounts([work.id, home.id])
        try database.save(school)
        #expect(try database.accounts() == [work, home, school])
    }

    @Test func savingAnAccountAgainKeepsItsPlace() throws {
        let database = try MailDatabase(url: url)
        for account in [home, work, school] { try database.save(account) }
        try database.save(home)
        #expect(try database.accounts() == [home, work, school])
    }

    @Test func accountsAnOrderLeavesOutFollowItInTheirOldOrder() throws {
        let database = try MailDatabase(url: url)
        for account in [home, work, school] { try database.save(account) }
        try database.reorderAccounts([school.id])
        #expect(try database.accounts() == [school, home, work])
    }

    @Test func accountsAddedBeforeOrderingKeepTheOrderTheyWereAdded() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path)
        try MailDatabase.migrator.migrate(pool, upTo: "v25-contact-photos")
        try pool.write { db in
            for (id, minutesAgo) in [("late", 1), ("early", 30), ("middle", 10)] {
                try db.execute(
                    sql: "INSERT INTO account (id, email, color, createdAt) VALUES (?, ?, 'teal', ?)",
                    arguments: [id, "\(id)@example.com", Date.now.addingTimeInterval(Double(-60 * minutesAgo))])
            }
        }
        try pool.close()

        let database = try MailDatabase(url: url)
        #expect(try database.accounts().map(\.id.rawValue) == ["early", "middle", "late"])
        try database.save(
            Account(id: AccountID(rawValue: "new"), email: "new@example.com", color: .blue, service: .gmail))
        #expect(try database.accounts().map(\.id.rawValue) == ["early", "middle", "late", "new"])
    }
}
