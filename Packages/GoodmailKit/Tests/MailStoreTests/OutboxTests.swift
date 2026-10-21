import Foundation
import MailCore
import Testing

@testable import MailStore

/// Actions apply locally at once, replay to the server in order, and survive a sync that runs before they replay.
struct OutboxTests {
    private let database: MailDatabase
    private let server = FakeMailServer()
    private let account = Account(id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// One clock for fetches and sends, so which came first is clear.
    private let clock = TickingClock(start: Self.now)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "OutboxTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func id(_ threadID: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account.id, threadID: threadID)
    }

    private func thread(_ threadID: String, unread: Bool = true) -> ThreadSummary {
        ThreadSummary(
            id: id(threadID), subject: "Subject \(threadID)", snippet: "",
            sender: Contact(name: nil, address: "a@example.com"), date: Self.now.addingTimeInterval(-3600),
            isUnread: unread, messageCount: 1, labelIDs: ["INBOX"])
    }

    /// Both sides start with the same mail, as after a sync.
    private func seed(_ threads: ThreadSummary...) throws {
        for thread in threads { server.set(thread.id.threadID, thread) }
        try database.upsert(threads)
    }

    private func commands() -> MailCommands {
        MailCommands(store: database, replay: { _ in }, now: clock.next)
    }

    private func outbox() -> Outbox {
        Outbox(accountID: account.id, provider: server, store: database, now: clock.next)
    }

    private func inbox() async throws -> [String] {
        var iterator = database.threads(labeled: "INBOX").makeAsyncIterator()
        return try await iterator.next()?.map(\.id.threadID) ?? []
    }

    @Test func archiveLeavesTheInboxAtOnceAndReplaysOnce() async throws {
        try seed(thread("t1"), thread("t2"))
        try commands().perform(.archive, on: [id("t1")])

        #expect(try await inbox() == ["t2"], "local first")
        #expect(server.performed.isEmpty)

        try await outbox().flush()
        #expect(server.performed.map(\.threadID) == ["t1"])
        #expect(try database.pendingIntents(for: account.id).isEmpty)
        try await outbox().flush()
        #expect(server.performed.count == 1, "a drained outbox sends nothing")
    }

    @Test func markingReadUpdatesTheFlagAndCachedMessages() async throws {
        try seed(thread("t1"))
        let message = Message(
            id: Message.ID(accountID: account.id, messageID: "m1"), threadID: "t1",
            from: Contact(name: nil, address: "a@example.com"), subject: "", date: Self.now,
            labelIDs: ["INBOX", "UNREAD"], body: MessageBody(plain: "hi"))
        try database.save([message], inThread: id("t1"))

        try commands().perform(.markRead(true), on: [id("t1")])

        #expect(try database.thread(id("t1"))?.isUnread == false)
        var messages = database.messages(inThread: id("t1")).makeAsyncIterator()
        #expect(try await messages.next()?.first?.isUnread == false)
    }

    @Test func undoQueuesTheInverse() async throws {
        try seed(thread("t1"))
        let commands = commands()
        let undo = try commands.perform(.archive, on: [id("t1")])
        try commands.undo(undo)

        #expect(try await inbox() == ["t1"])
        try await outbox().flush()
        #expect(
            server.performed.map(\.action) == [.archive, .modifyLabels(add: ["INBOX"], remove: [])],
            "both replay, in order, so the server ends where the reader did")
    }

    @Test func aSyncBeforeReplayDoesNotBringTheThreadBack() async throws {
        try seed(thread("t1"))
        server.set("t1", thread("t1"))  // touched on the server, so the next sync refetches it
        try commands().perform(.archive, on: [id("t1")])

        let engine = SyncEngine(accountID: account.id, provider: server, store: database, now: clock.next)
        try await engine.sync()
        try await engine.sync()
        #expect(try await inbox() == [], "the queued archive still shows")

        try await outbox().flush()
        try await engine.sync()
        #expect(try await inbox() == [])
        #expect(try database.pendingIntents(for: account.id).isEmpty)
    }

    @Test func aFetchThatBeganBeforeTheSendStillShowsTheAction() async throws {
        try seed(thread("t1"))
        try commands().perform(.archive, on: [id("t1")])
        let staleFetch = clock.next()
        try await outbox().flush()

        // The fetch began before the archive reached the server, so it still has the thread in the Inbox.
        try database.apply(StoreChanges(accountID: account.id, upserts: [thread("t1")], fetchedAt: staleFetch))
        #expect(try await inbox() == [], "the sent archive still shows over the older fetch")

        var archived = thread("t1")
        archived.labelIDs = []
        try database.apply(StoreChanges(accountID: account.id, upserts: [archived], fetchedAt: clock.next()))
        #expect(try await inbox() == [])
        let left = try await database.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM outbox") }
        #expect(left == 0, "a fetch after the send has it, so the intent is done")
    }

    @Test func messagesFetchedBeforeTheSendStayRead() async throws {
        try seed(thread("t1"))
        let message = Message(
            id: Message.ID(accountID: account.id, messageID: "m1"), threadID: "t1",
            from: Contact(name: nil, address: "a@example.com"), subject: "", date: Self.now,
            labelIDs: ["INBOX", "UNREAD"], body: MessageBody(plain: "hi"))
        try commands().perform(.markRead(true), on: [id("t1")])
        let staleFetch = clock.next()
        try await outbox().flush()
        try database.save([message], inThread: id("t1"), fetchedAt: staleFetch)

        var messages = database.messages(inThread: id("t1")).makeAsyncIterator()
        #expect(try await messages.next()?.first?.isUnread == false)
        #expect(try database.thread(id("t1"))?.isUnread == false)
    }

    @Test func intentsForDeletedThreadsAreDropped() async throws {
        try seed(thread("t1"), thread("t2"))
        try commands().perform(.trash, on: [id("t1"), id("t2")])
        server.set("t1", nil)

        try await outbox().flush()
        #expect(try database.pendingIntents(for: account.id).isEmpty)
        #expect(server.performed.map(\.threadID) == ["t1", "t2"])
    }

    @Test func aFailureStopsTheDrainAndKeepsTheRest() async throws {
        try seed(thread("t1"), thread("t2"))
        try commands().perform(.archive, on: [id("t1"), id("t2")])
        server.failPerform(with: URLError(.notConnectedToInternet))

        await #expect(throws: URLError.self) { try await outbox().flush() }
        #expect(try database.pendingIntents(for: account.id).count == 2)

        server.failPerform(with: nil)
        try await outbox().flush()
        #expect(try database.pendingIntents(for: account.id).isEmpty)
    }

    @Test func threadsThatArentStoredAreNotQueued() throws {
        let undo = try commands().perform(.archive, on: [id("missing")])
        #expect(undo.isEmpty)
        #expect(try database.pendingIntents(for: account.id).isEmpty)
    }
}
