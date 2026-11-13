import Foundation
import MailCore
import Testing

@testable import MailStore

struct AccountStoreTests {
    private let database: MailDatabase
    private let home = Account(id: AccountID(rawValue: "home"), email: "home@example.com", color: .teal)
    private let work = Account(id: AccountID(rawValue: "work"), email: "work@example.com", color: .orange)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AccountStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(home)
        try database.save(work)
    }

    @Test func aNewAccountHasNoNameUntilOneIsGiven() throws {
        #expect(try database.accounts().map(\.name) == [nil, nil])
    }

    @Test func updatingAnAccountKeepsItsPlaceAndItsMail() throws {
        try database.upsert([
            ThreadSummary(
                id: ThreadSummary.ID(accountID: home.id, threadID: "t1"), subject: "Hi", snippet: "",
                sender: Contact(name: nil, address: "a@example.com"), participants: [], date: .now,
                isUnread: true, messageCount: 1, labelIDs: ["INBOX"])
        ])
        var renamed = home
        renamed.name = "Idan Birman"
        renamed.color = .purple
        try database.update(renamed)

        #expect(try database.accounts() == [renamed, work])
        #expect(try database.thread(ThreadSummary.ID(accountID: home.id, threadID: "t1")) != nil)
    }
}
