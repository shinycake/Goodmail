import Foundation
import MailCore
import Testing

@testable import MailStore

/// The cache cap: bodies and attachment files are evicted least recently read first, and eviction leaves the
/// thread list and search as they were.
struct CacheCapTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "CacheCapTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func id(_ threadID: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account.id, threadID: threadID)
    }

    private func thread(_ threadID: String, labels: Set<String> = ["INBOX"]) -> ThreadSummary {
        ThreadSummary(
            id: id(threadID), subject: "Subject \(threadID)", snippet: "",
            sender: Contact(name: nil, address: "a@example.com"), date: Self.now, isUnread: false, messageCount: 1,
            labelIDs: labels)
    }

    private func message(_ threadID: String, bodyLength: Int = 1000) -> Message {
        Message(
            id: Message.ID(accountID: account.id, messageID: "m-\(threadID)"), threadID: threadID,
            from: Contact(name: nil, address: "a@example.com"), subject: "Subject \(threadID)", date: Self.now,
            body: MessageBody(html: nil, plain: "word " + String(repeating: "x", count: bodyLength)))
    }

    /// Stores a thread with one body last read `minutes` after the reference time.
    private func cache(_ threadID: String, readAtMinute minutes: Double, labels: Set<String> = ["INBOX"]) throws {
        try database.upsert([thread(threadID, labels: labels)])
        try database.save(
            [message(threadID)], inThread: id(threadID), fetchedAt: Self.now,
            accessedAt: Self.now.addingTimeInterval(minutes * 60))
    }

    private func cachedThreads() throws -> Set<String> {
        try Set(database.pool.read { try String.fetchAll($0, sql: "SELECT DISTINCT threadID FROM message") })
    }

    private func listed() async throws -> [String] {
        var iterator = database.threads(in: .inbox).makeAsyncIterator()
        return try await iterator.next()?.map(\.id.threadID) ?? []
    }

    /// What each thread cached by `cache` weighs; all of them weigh the same.
    private func bytesPerThread() throws -> Int {
        try database.cacheUsage().bodies / (try cachedThreads().count)
    }

    private func attachmentsDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "CacheCapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An attachment file as the reader keeps them: `<account>/<message>-<part>/<name>`, last opened at `minute`.
    private func attachment(
        _ name: String, bytes: Int, readAtMinute minute: Double, in root: URL
    ) throws {
        let folder = root.appending(path: "a1/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "file.pdf")
        try Data(count: bytes).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Self.now.addingTimeInterval(minute * 60)], ofItemAtPath: file.path)
    }

    private func attachmentFolders(in root: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "a1").path))
    }

    // MARK: Size accounting

    @Test func bodiesAreCountedByTheirBytes() throws {
        #expect(try database.cacheUsage() == MailDatabase.CacheUsage(bodies: 0, attachments: 0))
        let small = message("t1", bodyLength: 10)
        try database.upsert([thread("t1"), thread("t2")])
        try database.save([small], inThread: id("t1"))
        let encoded = try JSONEncoder().encode(small).count
        // The JSON as stored, and the text search finds the body by.
        #expect(try database.cacheUsage().bodies == encoded + "word xxxxxxxxxx".utf8.count)

        let before = try database.cacheUsage().bodies
        try database.save([message("t2", bodyLength: 5000)], inThread: id("t2"))
        #expect(try database.cacheUsage().bodies > before + 5000)

        try database.save([message("t2", bodyLength: 10)], inThread: id("t2"))
        #expect(try database.cacheUsage().bodies == before * 2, "saving again replaces what was counted")
        try database.apply(StoreChanges(accountID: account.id, deletions: ["t1"]))
        #expect(try database.cacheUsage().bodies == before, "a deleted thread's bodies leave the count")
    }

    @Test func attachmentFilesAreCountedWithTheBodies() throws {
        let root = try attachmentsDirectory()
        try cache("t1", readAtMinute: 0)
        try attachment("m1-1", bytes: 100, readAtMinute: 0, in: root)
        try attachment("m2-1", bytes: 50, readAtMinute: 0, in: root)
        let usage = try database.cacheUsage(attachments: root)
        #expect(usage.attachments == 150)
        #expect(usage.total == usage.bodies + 150)
        #expect(try database.cacheUsage().attachments == 0, "without a folder there are none to count")
    }

    @Test func aCacheWithinTheLimitIsLeftAlone() throws {
        try cache("t1", readAtMinute: 0)
        try cache("t2", readAtMinute: 1)
        let usage = try database.cacheUsage().total
        #expect(try database.trimCache(to: usage) == MailDatabase.CacheTrim())
        #expect(try cachedThreads() == ["t1", "t2"])
    }

    // MARK: Order

    @Test func theLeastRecentlyReadThreadsGoFirst() throws {
        try cache("t-old", readAtMinute: 0)
        try cache("t-mid", readAtMinute: 10)
        try cache("t-new", readAtMinute: 20)
        let each = try bytesPerThread()

        // Reading the oldest makes it the newest.
        try database.touchMessages(inThread: id("t-old"), at: Self.now.addingTimeInterval(30 * 60))
        var trim = try database.trimCache(to: each * 2)
        #expect(trim.threads == 1)
        #expect(trim.freedBytes == each)
        #expect(try cachedThreads() == ["t-old", "t-new"], "the middle one went")

        trim = try database.trimCache(to: each)
        #expect(trim.threads == 1)
        #expect(try cachedThreads() == ["t-old"])
        #expect(try database.cacheUsage().bodies == each)
    }

    @Test func evictsUntilTheCacheFits() throws {
        for (index, name) in ["a", "b", "c", "d"].enumerated() { try cache(name, readAtMinute: Double(index)) }
        let each = try bytesPerThread()
        let trim = try database.trimCache(to: each + each / 2)
        #expect(trim.threads == 3)
        #expect(try cachedThreads() == ["d"])
        #expect(try database.cacheUsage().total <= each + each / 2)
    }

    @Test func aThreadsBodiesGoTogether() throws {
        try database.upsert([thread("t1"), thread("t2")])
        let first = message("t1")
        var second = message("t1")
        second = Message(
            id: Message.ID(accountID: account.id, messageID: "m-t1-b"), threadID: "t1", from: second.from,
            subject: second.subject, date: Self.now, body: second.body)
        try database.save([first, second], inThread: id("t1"), accessedAt: Self.now)
        try database.save([message("t2")], inThread: id("t2"), accessedAt: Self.now.addingTimeInterval(60))
        try database.trimCache(to: try database.cacheUsage().bodies - 1)
        #expect(try cachedThreads() == ["t2"], "no thread is left half cached")
    }

    @Test func attachmentsAndBodiesShareOneOrder() throws {
        let root = try attachmentsDirectory()
        try cache("t1", readAtMinute: 0)
        try cache("t2", readAtMinute: 20)
        try attachment("m1-1", bytes: 400, readAtMinute: 10, in: root)
        try attachment("m2-1", bytes: 400, readAtMinute: 30, in: root)
        let total = try database.cacheUsage(attachments: root).total

        // One byte over: only the oldest thread goes.
        var trim = try database.trimCache(to: total - 1, attachments: root)
        #expect(trim == MailDatabase.CacheTrim(threads: 1, attachments: 0, freedBytes: try bytesPerThread()))
        #expect(try cachedThreads() == ["t2"])

        // The older attachment goes before the newer body and attachment.
        trim = try database.trimCache(to: try database.cacheUsage(attachments: root).total - 1, attachments: root)
        #expect(trim.attachments == 1)
        #expect(trim.threads == 0)
        #expect(try attachmentFolders(in: root) == ["m2-1"])
        #expect(try cachedThreads() == ["t2"])
    }

    // MARK: What stays

    @Test func evictionKeepsSummariesListsAndSearch() async throws {
        try cache("t1", readAtMinute: 0)
        try cache("t2", readAtMinute: 1)
        try database.trimCache(to: 0)
        #expect(try cachedThreads().isEmpty)

        #expect(try await listed().sorted() == ["t1", "t2"])
        var search = database.search("subject t1").makeAsyncIterator()
        #expect(try await search.next()?.map(\.id.threadID) == ["t1"], "the subject is still searchable")
        var bodies = database.search("xxxx").makeAsyncIterator()
        #expect(try await bodies.next()?.isEmpty == true, "an evicted body no longer matches, and nothing breaks")
        var messages = database.messages(inThread: id("t1")).makeAsyncIterator()
        #expect(try await messages.next()?.isEmpty == true, "the reader sees no body until it is fetched again")

        // Opening the thread fetches it again.
        try database.save([message("t1")], inThread: id("t1"))
        #expect(try cachedThreads() == ["t1"])
        var found = database.search("xxxx").makeAsyncIterator()
        #expect(try await found.next()?.map(\.id.threadID) == ["t1"])
    }

    @Test func draftsAndQueuedActionsAreNeverEvicted() throws {
        try cache("draft", readAtMinute: 0, labels: ["DRAFT"])
        try cache("queued", readAtMinute: 1)
        try cache("plain", readAtMinute: 2)
        _ = try database.enqueue(
            [OutboxIntent(threadID: "queued", action: .archive, createdAt: Self.now)], account: account.id)

        let trim = try database.trimCache(to: 0)
        #expect(trim.threads == 1)
        #expect(try cachedThreads() == ["draft", "queued"])
    }

    @Test func outgoingMessagesAreNotTheCachesToEvict() throws {
        try cache("t1", readAtMinute: 0)
        let draft = Draft(accountID: account.id)
        try database.enqueue(
            OutgoingMessage(draft: draft, purpose: .send, sendAt: Self.now.addingTimeInterval(10)))
        try database.trimCache(to: 0)
        #expect(try database.dueMessages(for: account.id, by: Self.now.addingTimeInterval(60)).count == 1)
    }

    // MARK: Recency

    @Test func prefetchedBodiesAreOlderThanOnesTheReaderOpened() throws {
        try database.upsert([thread("opened"), thread("prefetched")])
        let fetchedAt = Self.now.addingTimeInterval(3600)
        // The reader opened this thread at the time it was fetched.
        try database.save([message("opened")], inThread: id("opened"), fetchedAt: fetchedAt, accessedAt: fetchedAt)
        try database.savePrefetched([message("prefetched")], inThread: id("prefetched"), fetchedAt: fetchedAt)

        try database.trimCache(to: try database.cacheUsage().bodies - 1)
        #expect(try cachedThreads() == ["opened"], "fetched later, but not read")
    }

    @Test func prefetchingAThreadTheReaderJustOpenedKeepsItRecent() throws {
        try database.upsert([thread("t1"), thread("t2")])
        let opened = Self.now.addingTimeInterval(3600)
        try database.save([message("t1")], inThread: id("t1"), fetchedAt: opened, accessedAt: opened)
        try database.save([message("t2")], inThread: id("t2"), fetchedAt: Self.now, accessedAt: Self.now)
        // A prefetch that began before the reader opened t1 and finished after.
        try database.savePrefetched([message("t1")], inThread: id("t1"), fetchedAt: Self.now)

        try database.trimCache(to: try database.cacheUsage().bodies - 1)
        #expect(try cachedThreads() == ["t1"])
    }
}
