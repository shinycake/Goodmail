import Foundation

/// What the connection allows, asked before each download that nobody is waiting for.
public protocol NetworkPath: Sendable {
    /// Whether bulk downloads are fine now: Wi-Fi or another path that is neither expensive (cellular, a hotspot)
    /// nor constrained (Low Data Mode).
    var allowsBulkDownload: Bool { get }
}

/// The persistence prefetch needs. `MailStore` implements it; tests use the real store.
public protocol PrefetchStore: Sendable {
    /// Of the account's `newest` threads, outside Spam and Trash, those without cached bodies, newest first.
    func threadsWithoutBodies(account: AccountID, among newest: Int) throws -> [ThreadSummary.ID]
    /// Stores bodies nobody asked to read, so they are the first to go when the cache is full.
    func savePrefetched(_ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date) throws
}

/// Downloads the bodies of an account's newest threads ahead of the reader (ADR-007), so they open offline.
///
/// Runs beside sync, never inside it: a few fetches at a time, only while `path` allows bulk downloads, and
/// stopped by `cancel()`. A run converges: it fetches what is missing, so a stopped one is finished by the next.
public actor BodyPrefetcher {
    /// How many of the newest threads are kept with their bodies.
    public static let threadLimit = 500
    /// Fetches in flight at once.
    public static let concurrency = 3

    public nonisolated let accountID: AccountID
    private let provider: any MailProvider
    private let store: any PrefetchStore
    private let path: any NetworkPath
    private let threadLimit: Int
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
        threadLimit: Int = BodyPrefetcher.threadLimit,
        concurrency: Int = BodyPrefetcher.concurrency,
        now: @escaping @Sendable () -> Date = { .now },
        didFinish: @escaping @Sendable () async -> Void = {}
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.path = path
        self.threadLimit = threadLimit
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

    /// Fetches the bodies the newest threads lack, and returns how many threads it stored. Does nothing on a path
    /// that doesn't allow bulk downloads, and stops when the path changes, the task is cancelled or a fetch fails
    /// for any reason but its thread being gone.
    @discardableResult
    public func run() async -> Int {
        guard path.allowsBulkDownload,
            let missing = try? store.threadsWithoutBodies(account: accountID, among: threadLimit)
        else { return 0 }
        var remaining = missing.makeIterator()
        var stored = 0
        var failed = false
        let (provider, store, path, now) = (provider, store, path, now)
        await withTaskGroup(of: Outcome.self) { group in
            func launch() {
                guard !failed, !Task.isCancelled, path.allowsBulkDownload, let thread = remaining.next() else { return }
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
