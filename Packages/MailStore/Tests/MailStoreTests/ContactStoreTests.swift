import Foundation
import MailCore
import Testing

@testable import MailStore

/// Recipient suggestions from the people who wrote in.
struct ContactStoreTests {
    private let database: MailDatabase
    private let account = Account(id: AccountID(rawValue: "a1"), email: "Me@example.com", color: .teal)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ContactStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private var count = 0

    private mutating func thread(_ name: String?, _ address: String, daysAgo: Double = 0) -> ThreadSummary {
        count += 1
        return ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t\(count)"), subject: "", snippet: "",
            sender: Contact(name: name, address: address),
            date: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400), isUnread: false, messageCount: 1,
            labelIDs: ["INBOX"])
    }

    @Test mutating func matchesNameWordsAndAddressesMostFrequentFirst() throws {
        try database.upsert([
            thread("Dana Levi", "dana@example.com", daysAgo: 1),
            thread("Dana Levi", "DANA@example.com", daysAgo: 2),
            thread("Daniel Cohen", "dc@example.com"),
            thread(nil, "levi.office@example.com", daysAgo: 5),
            thread("Noah", "noah@example.com"),
            thread("Me", "me@example.com"),
        ])
        #expect(try database.contacts(matching: "dan").map(\.address) == ["dana@example.com", "dc@example.com"])
        #expect(
            try database.contacts(matching: "levi").map(\.address) == ["dana@example.com", "levi.office@example.com"])
        #expect(try database.contacts(matching: "Coh").first?.name == "Daniel Cohen")
        #expect(try database.contacts(matching: "me").isEmpty, "the account's own address isn't suggested")
        #expect(try database.contacts(matching: " ").isEmpty)
    }

    @Test mutating func wildcardsAreTypedLiterally() throws {
        try database.upsert([thread("Percent", "p@example.com"), thread("Under_score", "u@example.com")])
        #expect(try database.contacts(matching: "%").isEmpty)
        #expect(try database.contacts(matching: "Under_").map(\.address) == ["u@example.com"])
    }
}
