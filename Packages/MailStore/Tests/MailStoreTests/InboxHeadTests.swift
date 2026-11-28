import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// A device that keeps only the head of the Inbox: the sync stops at the limit, and the prune drops threads that
/// left the Inbox unless work is still queued on them.
struct InboxHeadTests {
    private let database: MailDatabase
    private let server = FakeMailServer(pageSize: 50)
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let clock = TickingClock(start: Self.now)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "InboxHeadTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func engine(_ scope: SyncScope) -> SyncEngine {
        SyncEngine(accountID: account.id, provider: server, store: database, scope: scope, now: clock.next)
    }

    private func thread(_ id: String, minutesAgo: Double, labels: Set<String> = ["INBOX"]) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id),
            subject: "Subject \(id)",
            snippet: "",
            sender: Contact(name: nil, address: "\(id)@example.com"),
            date: Self.now.addingTimeInterval(-minutesAgo * 60),
            isUnread: false,
            messageCount: 1,
            labelIDs: labels
        )
    }

    private func seedInbox(_ count: Int) {
        for index in 0..<count { server.set("t\(index)", thread("t\(index)", minutesAgo: Double(index))) }
    }

    private func storedThreads() throws -> Set<String> {
        try Set(database.read { try String.fetchAll($0, sql: "SELECT id FROM thread") })
    }

    // MARK: Sync

    @Test func inboxHeadStopsPagingAtItsLimit() async throws {
        seedInbox(300)
        try await engine(.inboxHead(limit: 100)).sync()

        let pages = server.queries.filter { $0.query.text == nil }
        #expect(pages.count == 2, "two pages of 50 reach the limit, and no third is asked for")
        #expect(pages.allSatisfy { $0.query.label == "INBOX" }, "only the Inbox")
        #expect(try storedThreads() == Set((0..<100).map { "t\($0)" }), "the newest 100")
        guard case .current = try database.syncState(for: account.id) else {
            Issue.record("sync should end current")
            return
        }
    }

    @Test func inboxHeadSkipsTheAddressBook() async throws {
        server.setContacts([Contact(name: "Ada", address: "ada@example.com")])
        seedInbox(3)
        try await engine(.inboxHead(limit: 100)).sync()

        #expect(server.contactRequests == 0)
        #expect(try database.addressBookDate(for: account.id) == nil)
    }

    @Test func theWindowStillFetchesEveryPage() async throws {
        seedInbox(300)
        try await engine(.window(.handheld)).sync()

        #expect(try storedThreads().count == 300)
        #expect(server.queries.contains { $0.query.label == "SENT" }, "every stage still runs")
    }

    @Test(arguments: [
        #"{"cursor":"7","startedAt":0,"generation":1,"stage":2,"pageToken":"50"}"#,
        #"{"cursor":"7","startedAt":0,"generation":1,"stage":0,"pageToken":"50","stored":50}"#,
    ])
    func aResyncSavedByStageListsAgainFromTheStart(saved: String) throws {
        let resync = try JSONDecoder().decode(Resync.self, from: Data(saved.utf8))
        #expect(resync == Resync(cursor: "7", startedAt: Date(timeIntervalSinceReferenceDate: 0), generation: 1))
        #expect(resync.position == .unplanned, "the stage numbered queries this build may list differently")
        #expect(resync.stored == 0)
    }

    @Test func aResyncKeepsItsPlaceThroughTheDatabase() throws {
        let query = ThreadQuery(label: "INBOX", since: Self.now)
        let resync = Resync(
            cursor: "7", startedAt: Self.now, generation: 1,
            position: .listing(
                query: query, pageToken: "50", next: [ThreadQuery(since: Self.now)], sweeping: ["INBOX"]),
            stored: 50)
        try database.apply(StoreChanges(accountID: account.id, progress: .resyncing(resync)))
        #expect(try database.syncState(for: account.id) == .resyncing(resync))
    }

    // MARK: Prune

    @Test func pruneDropsAThreadThatLeftTheInbox() async throws {
        server.set("kept", thread("kept", minutesAgo: 1))
        server.set("archived", thread("archived", minutesAgo: 2))
        let engine = engine(.inboxHead(limit: 100))
        try await engine.sync()
        server.set("archived", thread("archived", minutesAgo: 2, labels: []))
        try await engine.sync()

        #expect(try database.pruneOutsideInbox(account: account.id) == 1)
        #expect(try storedThreads() == ["kept"])
    }

    @Test func pruneKeepsAThreadWithAQueuedIntent() async throws {
        server.set("queued", thread("queued", minutesAgo: 1))
        try await engine(.inboxHead(limit: 100)).sync()
        _ = try database.enqueue(
            [OutboxIntent(threadID: "queued", action: .archive, createdAt: Self.now)], account: account.id)

        #expect(try database.pruneOutsideInbox(account: account.id) == 0)
        #expect(try storedThreads() == ["queued"])
    }

    @Test func pruneKeepsAThreadWithAQueuedReply() async throws {
        server.set("replied", thread("replied", minutesAgo: 1, labels: []))
        server.set("other", thread("other", minutesAgo: 2, labels: []))
        try await engine(.window(.handheld)).sync()
        let reply = Draft(accountID: account.id, threadID: "replied")
        try database.enqueue(OutgoingMessage(draft: reply, purpose: .send, sendAt: Self.now))

        #expect(try database.pruneOutsideInbox(account: account.id) == 1)
        #expect(try storedThreads() == ["replied"])
    }

    @Test func pruneLeavesOtherAccountsAlone() async throws {
        let other = Account(id: AccountID(rawValue: "a2"), email: "other@example.com", color: .teal, service: .gmail)
        try database.save(other)
        try database.apply(
            StoreChanges(
                accountID: other.id,
                upserts: [
                    ThreadSummary(
                        id: ThreadSummary.ID(accountID: other.id, threadID: "elsewhere"), subject: "", snippet: "",
                        sender: Contact(name: nil, address: "x@example.com"), date: Self.now, isUnread: false,
                        messageCount: 1, labelIDs: [])
                ],
                fetchedAt: Self.now))

        #expect(try database.pruneOutsideInbox(account: account.id) == 0)
        #expect(try storedThreads() == ["elsewhere"])
    }
}
