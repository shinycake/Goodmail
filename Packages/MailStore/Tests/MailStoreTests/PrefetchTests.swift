import Foundation
import GRDB
import Synchronization
import Testing

@testable import MailCore
@testable import MailStore

/// Body prefetch against the real store and a fake server: it fetches the newest threads that lack bodies, no
/// more than its limit, and only on a path that allows bulk downloads.
struct PrefetchTests {
    /// A connection that allows what the test sets.
    final class FakePath: NetworkPath {
        private let current: Mutex<NetworkAllowance>
        init(_ allowance: NetworkAllowance = .unmetered) { current = Mutex(allowance) }
        var allowance: NetworkAllowance {
            get { current.withLock { $0 } }
            set { current.withLock { $0 = newValue } }
        }
    }

    private let database: MailDatabase
    private let server = FakeMailServer()
    private let path = FakePath()
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PrefetchTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func prefetcher(
        limit: Int = 500, meteredLimit: Int = 50, scope: PrefetchScope = .default, concurrency: Int = 1,
        at now: Date = PrefetchTests.now, hasRoom: Bool = true, didFinish: @escaping @Sendable () async -> Void = {}
    ) -> BodyPrefetcher {
        BodyPrefetcher(
            accountID: account.id, provider: server, store: database, path: path, scope: { scope },
            hasRoom: { hasRoom },
            threadLimit: limit, meteredThreadLimit: meteredLimit, concurrency: concurrency, now: { now },
            didFinish: didFinish)
    }

    /// Stores a thread and gives the server its message. Lower `hoursAgo` is newer.
    private func seed(_ threadID: String, hoursAgo: Double, labels: Set<String> = ["INBOX"]) throws {
        let id = ThreadSummary.ID(accountID: account.id, threadID: threadID)
        let date = Self.now.addingTimeInterval(-hoursAgo * 3600)
        try database.upsert([
            ThreadSummary(
                id: id, subject: "Subject \(threadID)", snippet: "",
                sender: Contact(name: nil, address: "a@example.com"), date: date, isUnread: false, messageCount: 1,
                labelIDs: labels)
        ])
        server.setMessages(
            [
                Message(
                    id: Message.ID(accountID: account.id, messageID: "m-\(threadID)"), threadID: threadID,
                    from: Contact(name: nil, address: "a@example.com"), subject: "Subject \(threadID)", date: date,
                    body: MessageBody(html: nil, plain: "body of \(threadID)"))
            ], inThread: threadID)
    }

    /// Dates the thread by a reply `hoursAgo`, as sync does when one arrives, and gives the server the reply too unless
    /// `onServer` is false.
    private func reply(in threadID: String, hoursAgo: Double, onServer: Bool = true) throws {
        let id = ThreadSummary.ID(accountID: account.id, threadID: threadID)
        let date = Self.now.addingTimeInterval(-hoursAgo * 3600)
        try database.upsert([
            ThreadSummary(
                id: id, subject: "Subject \(threadID)", snippet: "",
                sender: Contact(name: nil, address: "b@example.com"), date: date, isUnread: true, messageCount: 2,
                labelIDs: ["INBOX"])
        ])
        guard onServer else { return }
        let reply = Message(
            id: Message.ID(accountID: account.id, messageID: "r-\(threadID)"), threadID: threadID,
            from: Contact(name: nil, address: "b@example.com"), subject: "Re: Subject \(threadID)", date: date,
            body: MessageBody(html: nil, plain: "reply in \(threadID)"))
        server.append(reply, inThread: threadID)
    }

    private func cachedMessages(in threadID: String) throws -> [String] {
        try database.pool.read {
            try String.fetchAll(
                $0, sql: "SELECT id FROM message WHERE threadID = ? ORDER BY date", arguments: [threadID])
        }
    }

    private func cached() throws -> Set<String> {
        try Set(database.pool.read { try String.fetchAll($0, sql: "SELECT DISTINCT threadID FROM message") })
    }

    @Test func fetchesTheBodiesOfThreadsThatLackThem() async throws {
        try seed("t1", hoursAgo: 1)
        try seed("t2", hoursAgo: 2)
        let stored = await prefetcher().run()
        #expect(stored == 2)
        #expect(try cached() == ["t1", "t2"])
        #expect(server.messageRequests == ["t1", "t2"], "newest first")
    }

    @Test func picksTheNewestThreadsWithoutBodiesAndStopsAtTheLimit() async throws {
        for (index, name) in ["t1", "t2", "t3", "t4", "t5"].enumerated() {
            try seed(name, hoursAgo: Double(index + 1))
        }
        // t2 is read already, and counts toward the newest three.
        try database.save(
            try await server.messages(inThread: "t2"), inThread: .init(accountID: account.id, threadID: "t2"))
        let before = server.messageRequests.count

        let stored = await prefetcher(limit: 3).run()
        #expect(stored == 2)
        #expect(Array(server.messageRequests.dropFirst(before)) == ["t1", "t3"], "t4 and t5 are beyond the limit")
        #expect(try cached() == ["t1", "t2", "t3"])
    }

    @Test func aSecondRunHasNothingLeftToFetch() async throws {
        try seed("t1", hoursAgo: 1)
        try seed("t2", hoursAgo: 2)
        await prefetcher().run()
        let requests = server.messageRequests.count
        #expect(await prefetcher().run() == 0)
        #expect(server.messageRequests.count == requests)
    }

    @Test func skipsSpamAndTrash() async throws {
        try seed("spam", hoursAgo: 1, labels: ["SPAM"])
        try seed("trash", hoursAgo: 2, labels: ["TRASH"])
        try seed("inbox", hoursAgo: 3)
        try seed("archived", hoursAgo: 4, labels: [])
        await prefetcher(limit: 2).run()
        #expect(try cached() == ["inbox", "archived"], "they don't use up the limit either")
    }

    @Test func doesNothingOfflineOrInLowDataMode() async throws {
        try seed("t1", hoursAgo: 1)
        path.allowance = .none
        #expect(await prefetcher().run() == 0)
        #expect(server.messageRequests.isEmpty)
        #expect(try cached().isEmpty)

        path.allowance = .unmetered
        #expect(await prefetcher().run() == 1, "it picks up when the path allows")
    }

    @Test func doesNothingWhenTheCacheHasNoRoom() async throws {
        try seed("t1", hoursAgo: 1)
        #expect(await prefetcher(hasRoom: false).run() == 0)
        #expect(server.messageRequests.isEmpty)
        #expect(await prefetcher(hasRoom: true).run() == 1)
    }

    @Test func onCellularFetchesOnlyTheNewestFew() async throws {
        for index in 1...4 { try seed("t\(index)", hoursAgo: Double(index)) }
        path.allowance = .metered
        #expect(await prefetcher(meteredLimit: 2).run() == 2)
        #expect(try cached() == ["t1", "t2"])
    }

    @Test(arguments: [PrefetchScope.wifiOnly, .never])
    func aScopeWithoutCellularFetchesNothingThere(scope: PrefetchScope) async throws {
        try seed("t1", hoursAgo: 1)
        path.allowance = .metered
        #expect(await prefetcher(scope: scope).run() == 0)
        #expect(server.messageRequests.isEmpty)
    }

    @Test func neverFetchesNothingOnWiFiEither() async throws {
        try seed("t1", hoursAgo: 1)
        #expect(await prefetcher(scope: .never).run() == 0)
        #expect(server.messageRequests.isEmpty)
    }

    @Test func stopsWhenThePathAllowsNoMore() async throws {
        try seed("t1", hoursAgo: 1)
        try seed("t2", hoursAgo: 2)
        try seed("t3", hoursAgo: 3)
        // Allows the run to start and the first fetch to launch, then nothing.
        let path = SteppingPath([.unmetered, .unmetered], then: .none)
        let prefetcher = BodyPrefetcher(
            accountID: account.id, provider: server, store: database, path: path, concurrency: 1)
        #expect(await prefetcher.run() == 1)
        #expect(server.messageRequests == ["t1"])
    }

    @Test func droppingToCellularStopsOnceTheNewestFewAreFetched() async throws {
        for index in 1...5 { try seed("t\(index)", hoursAgo: Double(index)) }
        // Wi-Fi to start the run and launch the first fetch, then cellular.
        let path = SteppingPath([.unmetered, .unmetered], then: .metered)
        let prefetcher = BodyPrefetcher(
            accountID: account.id, provider: server, store: database, path: path, meteredThreadLimit: 2,
            concurrency: 1)
        #expect(await prefetcher.run() == 2)
        #expect(server.messageRequests == ["t1", "t2"])
    }

    @Test func atMostCapsTheRun() async throws {
        for index in 1...4 { try seed("t\(index)", hoursAgo: Double(index)) }
        #expect(await prefetcher().run(atMost: 3) == 3)
        #expect(try cached() == ["t1", "t2", "t3"], "the newest first")
    }

    @Test func fetchesAThreadAgainWhenANewerMessageCame() async throws {
        try seed("t1", hoursAgo: 3)
        await prefetcher(at: Self.now.addingTimeInterval(-2 * 3600)).run()
        try reply(in: "t1", hoursAgo: 1)

        #expect(await prefetcher().run() == 1)
        #expect(try cachedMessages(in: "t1") == ["m-t1", "r-t1"])
        #expect(await prefetcher().run() == 0, "it has them all now")
    }

    @Test func aMessageTheThreadNeverReturnsIsGivenUpOnAfterAnHour() async throws {
        try seed("t1", hoursAgo: 3)
        // The thread says a message came an hour and a half ago, but the server leaves it out of the thread.
        try reply(in: "t1", hoursAgo: 1.5, onServer: false)
        #expect(await prefetcher().run() == 1, "fetched once, when it lacked any body")
        #expect(await prefetcher().run() == 0, "fetched more than an hour after the thread's date: whole")
    }

    @Test func aMessageTheThreadLeavesOutIsAskedForAgainWithinTheHour() async throws {
        try seed("t1", hoursAgo: 3)
        try reply(in: "t1", hoursAgo: 0.5, onServer: false)
        await prefetcher().run()
        #expect(await prefetcher().run() == 1, "it may still be on its way to the server's thread")
    }

    @Test func aFailedFetchStopsTheRun() async throws {
        try seed("t1", hoursAgo: 1)
        try seed("t2", hoursAgo: 2)
        try seed("t3", hoursAgo: 3)
        server.failMessages(with: URLError(.notConnectedToInternet))
        #expect(await prefetcher().run() == 0)
        #expect(server.messageRequests == ["t1"], "the rest wait for the network")
        #expect(try cached().isEmpty)

        server.failMessages(with: nil)
        #expect(await prefetcher().run() == 3)
    }

    @Test func aThreadThatIsGoneIsSkipped() async throws {
        try seed("t1", hoursAgo: 1)
        try seed("t2", hoursAgo: 2)
        server.failMessages(with: ProviderError.notFound)
        #expect(await prefetcher().run() == 0)
        #expect(server.messageRequests == ["t1", "t2"])
    }

    @Test func fetchesSeveralAtOnceUpToItsConcurrency() async throws {
        for index in 1...8 { try seed("t\(index)", hoursAgo: Double(index)) }
        #expect(await prefetcher(concurrency: 3).run() == 8)
        #expect(try cached().count == 8)
    }

    @Test func prefetchingLeavesTheThreadSummariesAsTheyWere() async throws {
        try seed("t1", hoursAgo: 1)
        var before = database.threads(in: .inbox).makeAsyncIterator()
        let summaries = try await before.next()
        await prefetcher().run()
        var after = database.threads(in: .inbox).makeAsyncIterator()
        #expect(try await after.next() == summaries)
    }

    @Test func startRunsInTheBackgroundAndReportsWhenDone() async throws {
        try seed("t1", hoursAgo: 1)
        let (finished, signal) = AsyncStream<Void>.makeStream()
        let prefetcher = prefetcher { signal.yield() }
        await prefetcher.start()
        await prefetcher.start()
        var iterator = finished.makeAsyncIterator()
        await iterator.next(isolation: #isolation)
        #expect(try cached() == ["t1"])
        #expect(server.messageRequests == ["t1"], "the second start joined the first run")
    }

    @Test(.timeLimit(.minutes(1)))
    func startingWhileACancelledRunWindsDownRunsAgain() async throws {
        try seed("t1", hoursAgo: 1)
        try seed("t2", hoursAgo: 2)
        let gate = Gate()
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        server.onMessagesRequested { thread in
            arrived.yield(thread)
            if thread == "t1" { await gate.wait() }
        }
        let (finished, signal) = AsyncStream<Void>.makeStream()
        let prefetcher = prefetcher { signal.yield() }
        await prefetcher.start()
        var requests = arrivals.makeAsyncIterator()
        _ = await requests.next()
        await prefetcher.cancel()
        await prefetcher.start()
        await gate.open()

        var runs = finished.makeAsyncIterator()
        await runs.next(isolation: #isolation)
        await runs.next(isolation: #isolation)
        #expect(try cached() == ["t1", "t2"], "the start after the cancel began a run of its own")
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingAgainDropsAStartThatWaitedForTheRunToStop() async throws {
        try seed("t1", hoursAgo: 1)
        try seed("t2", hoursAgo: 2)
        let gate = Gate()
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        server.onMessagesRequested { thread in
            arrived.yield(thread)
            await gate.wait()
        }
        let (finished, signal) = AsyncStream<Void>.makeStream()
        let prefetcher = prefetcher { signal.yield() }
        await prefetcher.start()
        var requests = arrivals.makeAsyncIterator()
        _ = await requests.next()
        await prefetcher.cancel()
        await prefetcher.start()
        await prefetcher.cancel()
        await gate.open()

        var runs = finished.makeAsyncIterator()
        await runs.next(isolation: #isolation)
        #expect(await prefetcher.isIdle, "the second cancel took back the start before it")
        #expect(server.messageRequests == ["t1"])
    }

    @Test func cancelStopsARunBeforeItFetches() async throws {
        try seed("t1", hoursAgo: 1)
        let prefetcher = prefetcher()
        // A task added to a cancelled group starts cancelled.
        let fetched = await withTaskGroup(of: Int.self) { group in
            group.cancelAll()
            group.addTask { await prefetcher.run() }
            return await group.next()
        }
        #expect(fetched == 0)
        #expect(server.messageRequests.isEmpty)
    }
}

/// Allows `steps` in turn, one per question, then `rest` from then on.
private final class SteppingPath: NetworkPath {
    private let remaining: Mutex<[NetworkAllowance]>
    private let rest: NetworkAllowance
    init(_ steps: [NetworkAllowance], then rest: NetworkAllowance) {
        remaining = Mutex(steps)
        self.rest = rest
    }
    var allowance: NetworkAllowance {
        remaining.withLock { $0.isEmpty ? rest : $0.removeFirst() }
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
