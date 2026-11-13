import Foundation
import MailCore
import Testing

@testable import MailStore

struct ThreadStoreTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ThreadStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func thread(_ id: String, minutesAgo: Double, labels: Set<String> = ["INBOX"]) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id),
            subject: "Subject \(id)",
            snippet: "Snippet \(id)",
            sender: Contact(name: "Sender \(id)", address: "\(id)@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60),
            isUnread: true,
            messageCount: 1,
            labelIDs: labels
        )
    }

    private func inbox() async throws -> [ThreadSummary] {
        var iterator = database.threads(in: .inbox).makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    @Test func accountsRoundTripInTheOrderAdded() throws {
        let second = Account(id: AccountID(rawValue: "a2"), email: "two@example.com", color: .orange, service: .gmail)
        try database.save(second)
        #expect(try database.accounts() == [account, second])
    }

    @Test func inboxIsNewestFirstAndExcludesOtherLabels() async throws {
        try database.upsert([
            thread("old", minutesAgo: 60),
            thread("new", minutesAgo: 1),
            thread("archived", minutesAgo: 5, labels: ["CATEGORY_UPDATES"]),
        ])
        let threads = try await inbox()
        #expect(threads.map(\.id.threadID) == ["new", "old"])
        #expect(threads[0] == thread("new", minutesAgo: 1))
    }

    @Test func upsertUpdatesAThreadAndReplacesItsLabels() async throws {
        try database.upsert([thread("t", minutesAgo: 10, labels: ["INBOX", "STARRED"])])
        var updated = thread("t", minutesAgo: 0, labels: ["INBOX", "IMPORTANT"])
        updated.isUnread = false
        updated.messageCount = 3
        try database.upsert([updated])

        #expect(try await inbox() == [updated])
    }

    @Test func streamEmitsAgainAfterAWrite() async throws {
        var iterator = database.threads(in: .inbox).makeAsyncIterator()
        #expect(try await iterator.next() == [])
        try database.upsert([thread("t", minutesAgo: 0)])
        #expect(try await iterator.next()?.map(\.id.threadID) == ["t"])
    }

    @Test func hebrewTextSurvivesTheRoundTrip() async throws {
        var hebrew = thread("he", minutesAgo: 0)
        hebrew.subject = "סיכום פגישה"
        hebrew.sender = Contact(name: "יעל כהן", address: "yael@example.co.il")
        try database.upsert([hebrew])
        #expect(try await inbox() == [hebrew])
    }
}
