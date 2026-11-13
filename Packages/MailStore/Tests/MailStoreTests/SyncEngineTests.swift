import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailStore

/// The sync engine against the real store and a fake server: after any sequence of syncs, failures and
/// server changes, the local window must match the server.
struct SyncEngineTests {
    private let database: MailDatabase
    private let server = FakeMailServer()
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SyncEngineTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    /// Each sync starts a second later, as real ones do, so successive resyncs get distinct generations.
    private let clock = TickingClock(start: Self.now)

    private func engine() -> SyncEngine {
        SyncEngine(accountID: account.id, provider: server, store: database, now: clock.next)
    }

    private func thread(_ id: String, daysAgo: Double, labels: Set<String> = ["INBOX"]) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id),
            subject: "Subject \(id)",
            snippet: "",
            sender: Contact(name: nil, address: "\(id)@example.com"),
            date: Self.now.addingTimeInterval(-daysAgo * 86_400),
            isUnread: false,
            messageCount: 1,
            labelIDs: labels
        )
    }

    private func seed(_ threads: ThreadSummary...) {
        for thread in threads { server.set(thread.id.threadID, thread) }
    }

    private func local(_ label: String = "INBOX") async throws -> [String] {
        var iterator = database.threads(in: Mailbox(labelID: label)).makeAsyncIterator()
        return try await iterator.next()?.map(\.id.threadID) ?? []
    }

    private func allLocal() throws -> Set<String> {
        try Set(database.pool.read { try String.fetchAll($0, sql: "SELECT id FROM thread") })
    }

    @Test func firstSyncFillsTheWindowInboxFirst() async throws {
        seed(
            thread("new", daysAgo: 1),
            thread("inbox-60d", daysAgo: 60),
            thread("inbox-120d", daysAgo: 120),
            thread("receipt-20d", daysAgo: 20, labels: ["Label_1"]),
            thread("receipt-45d", daysAgo: 45, labels: ["Label_1"]),
            thread("sent-80d", daysAgo: 80, labels: ["SENT"])
        )
        try await engine().sync()

        #expect(
            try allLocal() == ["new", "inbox-60d", "receipt-20d", "sent-80d"],
            "90 days for Inbox and Sent, 30 for the rest")
        #expect(try await local() == ["new", "inbox-60d"])
        #expect(server.queries.first?.query.label == "INBOX")
        #expect(try database.labels(for: account.id).map(\.id) == ["INBOX", "Label_1"])
        guard case .current(let cursor) = try database.syncState(for: account.id) else {
            Issue.record("sync should end current")
            return
        }
        #expect(cursor == (try await server.currentCursor()))
    }

    @Test func incrementalSyncRefetchesChangedThreadsAndDropsDeletedOnes() async throws {
        seed(thread("a", daysAgo: 1), thread("b", daysAgo: 2), thread("c", daysAgo: 3))
        try await engine().sync()

        server.set("a", thread("a", daysAgo: 1, labels: []))  // archived
        server.set("b", nil)  // deleted
        server.set("d", thread("d", daysAgo: 0))  // arrived
        try await engine().sync()

        #expect(try await local() == ["d", "c"])
        #expect(try allLocal() == ["a", "c", "d"], "archived mail stays local, out of the Inbox")
    }

    @Test func expiredCursorResyncsAndSweepsWhatVanished() async throws {
        seed(thread("kept", daysAgo: 1), thread("deleted", daysAgo: 2), thread("archived", daysAgo: 50))
        try await engine().sync()
        // Older mail the user scrolled to; outside the window, so a resync must leave it alone.
        try database.apply(StoreChanges(accountID: account.id, upserts: [thread("old", daysAgo: 200)]))

        server.set("deleted", nil)
        server.set("archived", thread("archived", daysAgo: 50, labels: []))
        server.expireCursors()
        try await engine().sync()

        #expect(try allLocal() == ["kept", "old"])
        #expect(try await local() == ["kept", "old"])
    }

    @Test func resyncInterruptedMidwayResumesFromTheLastSavedPage() async throws {
        seed(
            thread("i1", daysAgo: 1), thread("i2", daysAgo: 2), thread("i3", daysAgo: 3), thread("i4", daysAgo: 4),
            thread("i5", daysAgo: 5)
        )
        server.failPageRequest(after: 2)
        await #expect(throws: URLError.self) { try await engine().sync() }
        #expect(try await local() == ["i1", "i2", "i3", "i4"], "two pages landed before the failure")

        server.failPageRequest(after: 100)
        let before = server.queries.count
        try await engine().sync()

        let resumed = server.queries[before]
        #expect(resumed.query.label == "INBOX")
        #expect(resumed.pageToken == "4", "the first two pages are not fetched again")
        #expect(try await local() == ["i1", "i2", "i3", "i4", "i5"])
        #expect(try database.syncState(for: account.id).map { if case .current = $0 { true } else { false } } == true)
    }

    @Test func changesDuringTheResyncAreCaughtRightAfterIt() async throws {
        seed(thread("a", daysAgo: 1))
        let engine = engine()
        try await engine.sync()
        server.set("late", thread("late", daysAgo: 0))
        try await engine.sync()
        #expect(try await local() == ["late", "a"])
    }

    @Test func concurrentSyncsShareOneRun() async throws {
        seed(thread("a", daysAgo: 1))
        let engine = engine()
        try await engine.sync()
        let before = server.changeRequests

        async let first: Void = engine.sync()
        async let second: Void = engine.sync()
        _ = try await (first, second)
        #expect(server.changeRequests - before <= 2)
        #expect(server.changeRequests - before >= 1)
    }

    @Test func backfillFetchesPagesOlderThanTheWindowUntilNoneRemain() async throws {
        seed(
            thread("recent", daysAgo: 1), thread("old1", daysAgo: 100), thread("old2", daysAgo: 110),
            thread("old3", daysAgo: 120)
        )
        let engine = engine()
        try await engine.sync()
        #expect(try await local() == ["recent"])

        // Pages of two, overlapping by the oldest local thread.
        #expect(try await engine.backfill(.inbox))
        #expect(try await local() == ["recent", "old1"])
        #expect(try await engine.backfill(.inbox))
        #expect(try await local() == ["recent", "old1", "old2"])
        #expect(try await engine.backfill(.inbox) == false)
        #expect(try await local() == ["recent", "old1", "old2", "old3"])
    }

    @Test func backfillFillsAMailboxTheResyncLeftOut() async throws {
        seed(thread("inbox", daysAgo: 1), thread("binned", daysAgo: 2, labels: ["TRASH"]))
        let engine = engine()
        try await engine.sync()
        #expect(try await local("TRASH") == [], "the resync's window skips Trash, as Gmail's lists do")

        #expect(try await engine.backfill(.trash) == false, "one page held it all")
        #expect(try await local("TRASH") == ["binned"])
    }

    @Test func searchStoresTheProvidersMatchesAndReturnsThem() async throws {
        seed(
            thread("recent", daysAgo: 1), thread("old-invoice", daysAgo: 400, labels: []),
            thread("new-invoice", daysAgo: 2), thread("binned-invoice", daysAgo: 3, labels: ["TRASH"])
        )
        let page = try await engine().search("invoice")
        #expect(page.ids.map(\.threadID) == ["new-invoice", "old-invoice"])
        #expect(!page.hasMore)
        #expect(try allLocal() == ["new-invoice", "old-invoice"])
        #expect(server.queries.last?.query == ThreadQuery(text: "invoice"))
    }

    @Test func searchPagesOnFromTheTokenItGave() async throws {
        seed(
            thread("a-invoice", daysAgo: 1), thread("b-invoice", daysAgo: 2), thread("c-invoice", daysAgo: 3),
            thread("other", daysAgo: 4))
        let engine = engine()
        let first = try await engine.search("invoice")
        #expect(first.ids.map(\.threadID) == ["a-invoice", "b-invoice"], "the fake's pages hold two")
        let token = try #require(first.next[account.id])

        let second = try await engine.search("invoice", pageToken: token)
        #expect(second.ids.map(\.threadID) == ["c-invoice"])
        #expect(!second.hasMore)
        #expect(server.queries.last == FakeMailServer.Query(query: ThreadQuery(text: "invoice"), pageToken: token))
        #expect(try allLocal() == ["a-invoice", "b-invoice", "c-invoice"])
    }

    @Test func syncKeepsTheSignatureAndAFailedReadLeavesItAlone() async throws {
        server.setSignature("Dana\nGoodmail")
        try await engine().sync()
        #expect(try database.signature(for: account.id) == "Dana\nGoodmail")

        server.setSignature(nil)
        try await engine().sync()
        #expect(try database.signature(for: account.id) == "Dana\nGoodmail", "mail syncs; the signature stays")

        server.setSignature("")
        try await engine().sync()
        #expect(try database.signature(for: account.id) == nil)
    }

    @Test func theAddressBookIsFetchedOnceADayAndAFailureLeavesMailAlone() async throws {
        let dana = Contact(name: "Dana Levi", address: "dana@example.com")
        server.setContacts([dana])
        let engine = engine()
        try await engine.sync()
        try await engine.sync()
        #expect(server.contactRequests == 1, "fresh for a day")
        #expect(try database.contacts(matching: "dana") == [dana])

        server.setContacts(nil)
        let tomorrow = SyncEngine(
            accountID: account.id, provider: server, store: database,
            now: { Self.now.addingTimeInterval(SyncEngine.addressBookAge + 60) })
        try await tomorrow.sync()
        try await tomorrow.sync()
        #expect(server.contactRequests == 2, "a refusal isn't asked again on every sync")
        #expect(try database.contacts(matching: "dana") == [dana], "the last address book stays")
    }

    @Test func backfillSkipsAnotherAccountsLabel() async throws {
        seed(thread("t", daysAgo: 200, labels: ["Label_1"]))
        let other = Mailbox(labelID: "Label_1", accountID: AccountID(rawValue: "someone-else"))
        #expect(try await engine().backfill(other) == false)
        #expect(server.queries.isEmpty)
    }
}

final class TickingClock: Sendable {
    private let time: Mutex<Date>

    init(start: Date) {
        time = Mutex(start)
    }

    @Sendable func next() -> Date {
        time.withLock { now in
            defer { now += 1 }
            return now
        }
    }
}
