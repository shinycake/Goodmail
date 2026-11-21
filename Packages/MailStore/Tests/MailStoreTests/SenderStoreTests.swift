import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// VIPs and Block Sender's rules, as the store keeps them.
struct SenderStoreTests {
    private let database: MailDatabase
    private let dana = SenderAddress("dana@example.com")!
    private let noa = SenderAddress("noa@example.com")!

    init() throws {
        database = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "SenderStoreTests-\(UUID().uuidString).sqlite"))
    }

    @Test func vipsKeepTheirOrderAndComeOffAgain() throws {
        #expect(try database.vips() == VIPList())
        try database.setVIP(noa, true)
        try database.setVIP(dana, true)
        try database.setVIP(noa, true)
        #expect(try database.vips().senders == [noa, dana])
        try database.setVIP(noa, false)
        #expect(try database.vips().senders == [dana])
    }

    @Test func theVIPsAreFollowed() async throws {
        var updates = database.vipList().makeAsyncIterator()
        #expect(try await updates.next() == VIPList())
        try database.setVIP(dana, true)
        #expect(try await updates.next()?.senders == [dana])
    }

    @Test func blockingPutsTheRuleFirstOnceAndKeepsTheOthers() throws {
        let read = MailRule(name: "Read", condition: .all([]), actions: [.markRead])
        try database.setRules([read])

        try database.block(dana, named: "Block dana@example.com")
        try database.block(dana, named: "Block dana@example.com")
        try database.block(noa, named: "Block noa@example.com")

        let rules = try database.rules()
        #expect(rules.map(\.name) == ["Block noa@example.com", "Block dana@example.com", "Read"])
        #expect(rules.map(\.blockedSender) == [noa, dana, nil])
    }

    @Test func aRuleFromANewerBuildOutlastsABlock() throws {
        try database.setRules([MailRule(name: "Read", condition: .all([]), actions: [.markRead])])
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO mailRule (id, position, json) VALUES ('future', 1, '{\"from\":\"the future\"}')")
        }

        try database.block(dana, named: "Block dana@example.com")

        #expect(try database.rules().map(\.name) == ["Block dana@example.com", "Read"])
        let kept = try database.pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, position FROM mailRule ORDER BY position").map {
                "\($0["id"] as String)@\($0["position"] as Int)"
            }
        }
        #expect(kept.last == "future@2")
    }
}
