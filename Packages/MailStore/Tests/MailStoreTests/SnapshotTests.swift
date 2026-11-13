import Foundation
import MailCore
import Testing

@testable import MailStore

/// One-shot reads, for App Intents and widgets, which answer once instead of following the store.
struct SnapshotTests {
    private let database: MailDatabase
    private let account = AccountID(rawValue: "a1")

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SnapshotTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(Account(id: account, email: "tester@example.com", color: .teal, service: .gmail))
    }

    private func thread(_ id: String, minutesAgo: Double, labels: Set<String> = ["INBOX"]) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account, threadID: id),
            subject: "Subject \(id)",
            snippet: "Snippet \(id)",
            sender: Contact(name: "Sender \(id)", address: "\(id)@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60),
            isUnread: true,
            messageCount: 1,
            labelIDs: labels
        )
    }

    @Test func newestThreadsInAMailboxUpToTheLimit() throws {
        try database.upsert([
            thread("old", minutesAgo: 60), thread("new", minutesAgo: 1), thread("mid", minutesAgo: 30),
            thread("archived", minutesAgo: 0, labels: []),
        ])
        #expect(try database.threads(in: .inbox, limit: 2).map(\.id.threadID) == ["new", "mid"])
    }

    @Test func threadsByIDKeepTheirLabelsAndSkipTheMissing() throws {
        try database.upsert([thread("t", minutesAgo: 0, labels: ["SPAM"]), thread("u", minutesAgo: 5)])
        let ids = ["u", "gone", "t"].map { ThreadSummary.ID(accountID: account, threadID: $0) }
        let found = try database.threads(ids)
        #expect(found.map(\.id.threadID) == ["t", "u"])
        #expect(found[0].labelIDs == ["SPAM"])
    }

    @Test func matchingSearchesLikeTheSearchScreen() throws {
        var lunch = thread("lunch", minutesAgo: 0)
        lunch.subject = "Lunch on Friday"
        try database.upsert([lunch, thread("other", minutesAgo: 1)])
        #expect(try database.threads(matching: "lunch fri", limit: 10).map(\.id.threadID) == ["lunch"])
        #expect(try database.threads(matching: "  ", limit: 10).isEmpty)
    }

    @Test func cachedMessagesAreOldestFirst() throws {
        let summary = thread("t", minutesAgo: 0)
        try database.upsert([summary])
        let messages = [2, 1].map { minute in
            Message(
                id: Message.ID(accountID: account, messageID: "m\(minute)"), threadID: "t",
                from: Contact(name: nil, address: "a@example.com"), subject: "Hi",
                date: Date(timeIntervalSince1970: Double(minute) * 60), body: MessageBody(plain: "Body \(minute)"))
        }
        try database.save(messages, inThread: summary.id)
        #expect(try database.cachedMessages(inThread: summary.id).map(\.id.messageID) == ["m1", "m2"])
    }
}
