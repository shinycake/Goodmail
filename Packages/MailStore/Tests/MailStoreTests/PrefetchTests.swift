import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailStore

/// Body prefetch against the real store and a fake server: it fetches the newest threads that lack bodies, no
/// more than its limit, and only on a path that allows bulk downloads.
struct PrefetchTests {
    /// A connection that is cheap or not, as the test sets it.
    final class FakePath: NetworkPath {
        private let allowed: Mutex<Bool>
        init(allowed: Bool = true) { self.allowed = Mutex(allowed) }
        var allowsBulkDownload: Bool {
            get { allowed.withLock { $0 } }
            set { allowed.withLock { $0 = newValue } }
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
        limit: Int = 500, concurrency: Int = 1, didFinish: @escaping @Sendable () async -> Void = {}
    ) -> BodyPrefetcher {
        BodyPrefetcher(
            accountID: account.id, provider: server, store: database, path: path, threadLimit: limit,
            concurrency: concurrency, now: { Self.now }, didFinish: didFinish)
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

    @Test func doesNothingOnAnExpensivePath() async throws {
        try seed("t1", hoursAgo: 1)
        path.allowsBulkDownload = false
        #expect(await prefetcher().run() == 0)
        #expect(server.messageRequests.isEmpty)
        #expect(try cached().isEmpty)

        path.allowsBulkDownload = true
        #expect(await prefetcher().run() == 1, "it picks up when the path allows")
    }

    @Test func stopsWhenThePathBecomesExpensive() async throws {
        try seed("t1", hoursAgo: 1)
        try seed("t2", hoursAgo: 2)
        try seed("t3", hoursAgo: 3)
        // Allows the run to start and the first fetch to launch, then not.
        let path = CountingPath(allowing: 2)
        let prefetcher = BodyPrefetcher(
            accountID: account.id, provider: server, store: database, path: path, concurrency: 1)
        #expect(await prefetcher.run() == 1)
        #expect(server.messageRequests == ["t1"])
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
        await iterator.next()
        #expect(try cached() == ["t1"])
        #expect(server.messageRequests == ["t1"], "the second start joined the first run")
    }

    @Test func cancelStopsARunBeforeItFetches() async throws {
        try seed("t1", hoursAgo: 1)
        let prefetcher = prefetcher()
        let run = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await prefetcher.run()
        }
        #expect(await run.value == 0)
        #expect(server.messageRequests.isEmpty)
    }
}

/// Allows bulk downloads for its first `allowing` questions.
private final class CountingPath: NetworkPath {
    private let remaining: Mutex<Int>
    init(allowing count: Int) { remaining = Mutex(count) }
    var allowsBulkDownload: Bool {
        remaining.withLock { remaining in
            defer { remaining -= 1 }
            return remaining > 0
        }
    }
}
