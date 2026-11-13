import Foundation
import MailCore
import Testing

@testable import MailStore

struct MessageIndexTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private let other = Account(
        id: AccountID(rawValue: "a2"), email: "other@example.com", color: .blue, service: .gmail)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MessageIndexTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
        try database.save(other)
    }

    private let lunch = MessageIndexEntry(key: "m1", threadID: "t1", internetMessageID: "<a@x>")
    private let reply = MessageIndexEntry(key: "m2", threadID: "t1", internetMessageID: "<b@x>")
    private let news = MessageIndexEntry(key: "m3", threadID: "t2")

    @Test func looksEntriesUpByKeyThreadAndInternetMessageID() throws {
        try database.record([lunch, reply, news], account: account.id)
        #expect(try database.indexEntries(withKeys: ["m3", "m1", "gone"], account: account.id) == [lunch, news])
        #expect(try database.indexEntries(inThreads: ["t1"], account: account.id) == [lunch, reply])
        #expect(try database.indexEntries(withInternetMessageIDs: ["<b@x>"], account: account.id) == [reply])
    }

    @Test func recordingAKeyAgainReplacesItsEntry() throws {
        try database.record([lunch], account: account.id)
        let moved = MessageIndexEntry(key: "m1", threadID: "t9", internetMessageID: "<a@x>")
        try database.record([moved], account: account.id)
        #expect(try database.indexEntries(withKeys: ["m1"], account: account.id) == [moved])
    }

    @Test func entriesBelongToTheirAccount() throws {
        try database.record([lunch], account: account.id)
        try database.record([news], account: other.id)
        #expect(try database.indexEntries(withKeys: ["m1", "m3"], account: account.id) == [lunch])
        try database.forgetIndexEntries(withKeys: ["m3"], account: account.id)
        #expect(try database.indexEntries(withKeys: ["m3"], account: other.id) == [news], "another account's key")
    }

    @Test func forgettingAndRemovingTheAccountDropEntries() throws {
        try database.record([lunch, reply], account: account.id)
        try database.forgetIndexEntries(withKeys: ["m1"], account: account.id)
        #expect(try database.indexEntries(inThreads: ["t1"], account: account.id) == [reply])
        try database.removeAccount(account.id)
        #expect(try database.indexEntries(inThreads: ["t1"], account: account.id).isEmpty)
    }
}
