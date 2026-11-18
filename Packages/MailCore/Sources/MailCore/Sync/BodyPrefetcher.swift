public import Foundation

/// The persistence prefetch needs. `MailStore` implements it; tests use the real store.
public protocol PrefetchStore: Sendable {
    /// Of the account's `newest` threads, outside Spam and Trash, those whose cached bodies don't reach their newest
    /// message, or that have none, newest first.
    func threadsMissingBodies(account: AccountID, among newest: Int) throws -> [ThreadSummary.ID]
    /// Stores bodies nobody asked to read, so they are the first to go when the cache is full.
    func savePrefetched(_ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date) throws
}

/// Downloads the bodies of an account's newest threads ahead of the reader (ADR-007), so they open offline.
///
/// Runs beside sync, never inside it: a few fetches at a time, only as far as `path` and the reader's `scope` allow,
/// and stopped by `cancel()`. A run converges: it fetches what is missing, so a stopped one is finished by the next.
public actor BodyPrefetcher {
    /// How many of the newest threads are kept with their bodies on Wi-Fi.
    public static let threadLimit = 500
    /// How many on cellular: the ones a reader opens next, without spending their data on the rest.
    public static let meteredThreadLimit = 50
    /// Fetches in flight at once.
    public static let concurrency = 3

    public nonisolated let accountID: AccountID
    private let provider: any MailProvider
    private let store: any PrefetchStore
    private let path: any NetworkPath
    private let scope: @Sendable () -> PrefetchScope
    private let hasRoom: @Sendable () -> Bool
    private let threadLimit: Int
    private let meteredThreadLimit: Int
    private let concurrency: Int
    private let now: @Sendable () -> Date
    private let didFinish: @Sendable () async -> Void
    private var running: Task<Void, Never>?

    /// - Parameter didFinish: Called after each run that `start()` began, however it ended; the app trims the cache
    ///   there.
    public init(
        accountID: AccountID,
        provider: any MailProvider,
        store: any PrefetchStore,
        path: any NetworkPath,
        scope: @escaping @Sendable () -> PrefetchScope = { .default },
        hasRoom: @escaping @Sendable () -> Bool = { true },
        threadLimit: Int = BodyPrefetcher.threadLimit,
        meteredThreadLimit: Int = BodyPrefetcher.meteredThreadLimit,
        concurrency: Int = BodyPrefetcher.concurrency,
        now: @escaping @Sendable () -> Date = { .now },
        didFinish: @escaping @Sendable () async -> Void = {}
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.path = path
        self.scope = scope
        self.hasRoom = hasRoom
        self.threadLimit = threadLimit
        self.meteredThreadLimit = meteredThreadLimit
        self.concurrency = max(1, concurrency)
        self.now = now
        self.didFinish = didFinish
    }

    /// Runs in the background unless a run is already going.
    public func start() {
        guard running == nil else { return }
        running = Task {
            await run()
            running = nil
            await didFinish()
        }
    }

    /// Stops the run in progress, if any. Fetches already under way are abandoned.
    public func cancel() {
        running?.cancel()
    }

    private enum Outcome {
        case saved, skipped, failed
    }

    /// Fetches the bodies the newest threads lack, at most `count` of them, and returns how many threads it stored.
    /// Does nothing when the path or the scope allows nothing, or the cache has no room, and stops when the task is
    /// cancelled, a fetch fails for any reason but its thread being gone, or the path changes to allow fewer than it
    /// has fetched, as when Wi-Fi drops to cellular.
    @discardableResult
    public func run(atMost count: Int = .max) async -> Int {
        let limit = { [scope, path, threadLimit, meteredThreadLimit] in
            scope().threadLimit(on: path.allowance, unmetered: threadLimit, metered: meteredThreadLimit)
        }
        let newest = limit()
        guard newest > 0, hasRoom(), let missing = try? store.threadsMissingBodies(account: accountID, among: newest)
        else { return 0 }
        var remaining = missing.prefix(count).makeIterator()
        var launched = 0
        var stored = 0
        var failed = false
        let (provider, store, now) = (provider, store, now)
        await withTaskGroup(of: Outcome.self) { group in
            func launch() {
                guard !failed, !Task.isCancelled, launched < limit(), let thread = remaining.next() else { return }
                launched += 1
                group.addTask { await Self.fetch(thread, from: provider, into: store, at: now()) }
            }
            for _ in 0..<concurrency { launch() }
            for await outcome in group {
                switch outcome {
                case .saved: stored += 1
                case .skipped: break
                case .failed: failed = true
                }
                launch()
            }
        }
        return stored
    }

    private static func fetch(
        _ thread: ThreadSummary.ID, from provider: any MailProvider, into store: any PrefetchStore, at fetchedAt: Date
    ) async -> Outcome {
        do {
            let messages = try await provider.messages(inThread: thread.threadID)
            guard !messages.isEmpty else { return .skipped }
            try store.savePrefetched(messages, inThread: thread, fetchedAt: fetchedAt)
            return .saved
        } catch ProviderError.notFound {
            return .skipped
        } catch {
            return .failed
        }
    }
}
