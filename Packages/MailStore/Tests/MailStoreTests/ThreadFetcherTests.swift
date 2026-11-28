import Foundation
import GRDB
import Synchronization
import Testing

@testable import MailCore
@testable import MailStore

/// Fetching a thread before it opens: a row in view or under the finger starts it, and opening the thread joins it.
struct ThreadFetcherTests {
    private let database: MailDatabase
    private let server = FakeMailServer()
    private let path = PrefetchTests.FakePath()
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ThreadFetcherTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func fetcher(scope: PrefetchScope = .default) -> ThreadFetcher {
        ThreadFetcher(
            provider: { [server] _ in server }, store: database, path: path, scope: { scope }, now: { Self.now })
    }

    private func id(_ threadID: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account.id, threadID: threadID)
    }

    /// Stores a thread and gives the server its message, written `hoursAgo`.
    private func seed(_ threadID: String, hoursAgo: Double = 1) throws {
        let date = Self.now.addingTimeInterval(-hoursAgo * 3600)
        try database.upsert([
            ThreadSummary(
                id: id(threadID), subject: "Subject \(threadID)", snippet: "",
                sender: Contact(name: nil, address: "a@example.com"), date: date, isUnread: true, messageCount: 1,
                labelIDs: ["INBOX"])
        ])
        server.setMessages(
            [
                Message(
                    id: Message.ID(accountID: account.id, messageID: "m-\(threadID)"), threadID: threadID,
                    from: Contact(name: nil, address: "a@example.com"), subject: "Subject \(threadID)", date: date,
                    body: MessageBody(html: nil, plain: "body of \(threadID)"))
            ], inThread: threadID)
    }

    /// Each cached thread with when its bodies were last read.
    private func cached() throws -> [String: Date] {
        try database.read { db in
            try Dictionary(
                uniqueKeysWithValues: Row.fetchAll(
                    db, sql: "SELECT threadID, MAX(accessedAt) AS accessedAt FROM message GROUP BY threadID"
                ).map { ($0["threadID"] as String, $0["accessedAt"] as Date) })
        }
    }

    @Test func aRowInViewHasItsBodiesStoredAsUnread() async throws {
        try seed("t1", hoursAgo: 2)
        let fetcher = fetcher()
        await fetcher.readAhead([id("t1")], because: .visible)
        await fetcher.idle()
        #expect(try cached() == ["t1": Self.now.addingTimeInterval(-2 * 3600)], "dated by the mail, as prefetch dates")
    }

    @Test func openingStoresTheBodiesAsRead() async throws {
        try seed("t1", hoursAgo: 2)
        try await fetcher().load(id("t1"))
        #expect(try cached() == ["t1": Self.now])
    }

    @Test func openingJoinsTheFetchItsRowBegan() async throws {
        try seed("t1", hoursAgo: 2)
        let gate = Gate()
        server.onMessagesRequested { _ in await gate.wait() }
        let fetcher = fetcher()
        await fetcher.readAhead([id("t1")], because: .touched)
        async let opened: Void = fetcher.load(id("t1"))
        while await !fetcher.isJoined(id("t1")) { await Task.yield() }
        await gate.open()
        try await opened
        #expect(server.messageRequests == ["t1"])
        #expect(try cached() == ["t1": Self.now], "stored as read, since the reader joined it")
    }

    @Test func openingAfterLeavingTheForegroundStartsANewFetch() async throws {
        try seed("t1")
        let gate = Gate()
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        server.onMessagesRequested { thread in
            arrived.yield(thread)
            await gate.wait()
        }
        let fetcher = fetcher()
        await fetcher.readAhead([id("t1")], because: .touched)
        var iterator = arrivals.makeAsyncIterator()
        _ = await iterator.next()
        await fetcher.cancelReadAhead()
        async let opened: Void = fetcher.load(id("t1"))
        _ = await iterator.next()
        await gate.open()
        try await opened
        #expect(server.messageRequests == ["t1", "t1"], "the cancelled read ahead isn't joined")
        #expect(try cached() == ["t1": Self.now])
    }

    @Test func rowsWhoseBodiesAreCachedAreLeftAlone() async throws {
        try seed("t1")
        let fetcher = fetcher()
        try await fetcher.load(id("t1"))
        await fetcher.readAhead([id("t1")], because: .touched)
        await fetcher.readAhead([id("t1")], because: .visible)
        await fetcher.idle()
        #expect(server.messageRequests == ["t1"])
    }

    @Test(arguments: [
        (PrefetchScope.wifiOnly, NetworkAllowance.metered), (.never, .unmetered), (.wifiAndCellular, .none),
    ])
    func rowsInViewFollowTheScope(scope: PrefetchScope, allowance: NetworkAllowance) async throws {
        try seed("t1")
        path.allowance = allowance
        let fetcher = fetcher(scope: scope)
        await fetcher.readAhead([id("t1")], because: .visible)
        await fetcher.idle()
        #expect(server.messageRequests.isEmpty)
    }

    @Test func aTouchedRowIsFetchedOnAnyConnection() async throws {
        try seed("t1")
        path.allowance = .metered
        let fetcher = fetcher(scope: .never)
        await fetcher.readAhead([id("t1")], because: .touched)
        await fetcher.idle()
        #expect(try cached().keys.sorted() == ["t1"])
    }

    @Test func aTouchedRowWaitsOffline() async throws {
        try seed("t1")
        path.allowance = .none
        let fetcher = fetcher()
        await fetcher.readAhead([id("t1")], because: .touched)
        await fetcher.idle()
        #expect(server.messageRequests.isEmpty)
    }

    @Test func rowsInViewAreFetchedAFewAtATime() async throws {
        for index in 1...5 { try seed("t\(index)") }
        let gate = Gate()
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        server.onMessagesRequested { thread in
            arrived.yield(thread)
            await gate.wait()
        }
        let fetcher = fetcher()
        for index in 1...5 { await fetcher.readAhead([id("t\(index)")], because: .visible) }
        var iterator = arrivals.makeAsyncIterator()
        for _ in 0..<ThreadFetcher.visibleConcurrency { _ = await iterator.next() }
        #expect(server.messageRequests.count == ThreadFetcher.visibleConcurrency)

        await gate.open()
        await fetcher.idle()
        #expect(try cached().count == 5)
    }

    @Test func rowsComingUpTogetherStartNearestFirst() async throws {
        for index in 1...5 { try seed("t\(index)") }
        let gate = Gate()
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        server.onMessagesRequested { thread in
            arrived.yield(thread)
            await gate.wait()
        }
        let fetcher = fetcher()
        await fetcher.readAhead((1...5).map { id("t\($0)") }, because: .visible)
        var iterator = arrivals.makeAsyncIterator()
        var first: Set<String> = []
        for _ in 0..<ThreadFetcher.visibleConcurrency { first.insert(await iterator.next() ?? "") }
        #expect(first == ["t1", "t2", "t3"])

        await fetcher.skip([id("t4")])
        await gate.open()
        await fetcher.idle()
        #expect(server.messageRequests.sorted() == ["t1", "t2", "t3", "t5"], "a row that scrolled away is skipped")
    }

    @Test func leavingTheForegroundStopsReadingAhead() async throws {
        for index in 1...4 { try seed("t\(index)") }
        let gate = Gate()
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        server.onMessagesRequested { thread in
            arrived.yield(thread)
            await gate.wait()
        }
        let fetcher = fetcher()
        for index in 1...4 { await fetcher.readAhead([id("t\(index)")], because: .visible) }
        var iterator = arrivals.makeAsyncIterator()
        for _ in 0..<ThreadFetcher.visibleConcurrency { _ = await iterator.next() }

        await fetcher.cancelReadAhead()
        await gate.open()
        await fetcher.idle()
        #expect(try cached().isEmpty, "the fetches under way are dropped")
        #expect(server.messageRequests.count == ThreadFetcher.visibleConcurrency, "the waiting row never starts")
    }

    @Test(.timeLimit(.minutes(1)))
    func rowsComingBackAfterLeavingTheForegroundAreFetchedAgain() async throws {
        for index in 1...4 { try seed("t\(index)") }
        let gate = Gate()
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        // The first fetches never answer, as on a connection the app left behind; later ones answer at once.
        let held = Mutex(Set(["t1", "t2", "t3"]))
        server.onMessagesRequested { thread in
            arrived.yield(thread)
            if held.withLock({ $0.remove(thread) }) != nil { await gate.wait() }
        }
        let fetcher = fetcher()
        await fetcher.readAhead((1...3).map { id("t\($0)") }, because: .visible)
        var iterator = arrivals.makeAsyncIterator()
        for _ in 0..<ThreadFetcher.visibleConcurrency { _ = await iterator.next() }
        await fetcher.cancelReadAhead()

        await fetcher.readAhead([id("t1")], because: .touched)
        await fetcher.readAhead([id("t4")], because: .visible)
        await fetcher.idle()
        #expect(try cached().keys.sorted() == ["t1", "t4"], "the cancelled fetches hold neither their rows nor slots")
        await gate.open()
    }

    @Test func aFetchTheReaderJoinedOutlivesLeavingTheForeground() async throws {
        try seed("t1")
        let gate = Gate()
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        server.onMessagesRequested { thread in
            arrived.yield(thread)
            await gate.wait()
        }
        let fetcher = fetcher()
        await fetcher.readAhead([id("t1")], because: .touched)
        var iterator = arrivals.makeAsyncIterator()
        _ = await iterator.next()
        async let opened: Void = fetcher.load(id("t1"))
        // The load joins before the fetcher handles anything sent after it.
        while await !fetcher.isJoined(id("t1")) { await Task.yield() }
        await fetcher.cancelReadAhead()
        await gate.open()
        try await opened
        #expect(try cached().keys.sorted() == ["t1"])
    }
}

/// Holds whoever waits until it opens.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
