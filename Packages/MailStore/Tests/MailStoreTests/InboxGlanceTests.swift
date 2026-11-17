import Foundation
import MailCore
import Testing

@testable import MailStore

/// The Inbox at a glance: the newest threads, the pinned ones however old, and unread counts over the whole Inbox.
struct InboxGlanceTests {
    private let database: MailDatabase
    private let work = Account(
        id: AccountID(rawValue: "work"), email: "me@work.example", color: .orange, service: .gmail)
    private let home = Account(
        id: AccountID(rawValue: "home"), email: "me@home.example", color: .blue, service: .icloud)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "InboxGlanceTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(work)
        try database.save(home)
    }

    private func thread(
        _ id: String, in account: Account, minutesAgo: Double, unread: Bool = true, labels: Set<String> = ["INBOX"]
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Subject \(id)", snippet: "",
            sender: Contact(name: nil, address: "\(id)@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60), isUnread: unread, messageCount: 1,
            labelIDs: labels)
    }

    private func glance(limit: Int) async throws -> InboxGlance {
        var glances = database.inboxGlance(limit: limit).makeAsyncIterator()
        return try #require(try await glances.next())
    }

    @Test func newestThreadsThenOlderPinnedOnes() async throws {
        let old = thread("old", in: work, minutesAgo: 90)
        try database.upsert([
            old, thread("new", in: home, minutesAgo: 1), thread("mid", in: work, minutesAgo: 30),
            thread("archived", in: work, minutesAgo: 0, labels: []),
        ])
        try database.setPins([old.id: true])

        let glance = try await glance(limit: 2)
        #expect(glance.threads.map(\.id.threadID) == ["new", "mid", "old"])
        #expect(glance.pinned == [old.id])
        #expect(glance.accounts.map(\.id) == [work.id, home.id])
    }

    @Test func unreadCountsCoverTheWholeInbox() async throws {
        try database.upsert([
            thread("w1", in: work, minutesAgo: 1), thread("w2", in: work, minutesAgo: 2),
            thread("w3", in: work, minutesAgo: 3, unread: false), thread("h1", in: home, minutesAgo: 4),
            thread("h2", in: home, minutesAgo: 5, labels: []),
        ])
        let glance = try await glance(limit: 1)
        #expect(glance.unread == [work.id: 2, home.id: 1])
    }

    @Test func followsChanges() async throws {
        var glances = database.inboxGlance(limit: 5).makeAsyncIterator()
        #expect(try await glances.next()?.threads == [])
        try database.upsert([thread("t1", in: work, minutesAgo: 1)])
        #expect(try await glances.next()?.threads.map(\.id.threadID) == ["t1"])
    }
}
