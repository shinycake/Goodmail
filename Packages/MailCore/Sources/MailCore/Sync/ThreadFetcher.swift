public import Foundation

/// The persistence `ThreadFetcher` needs. `MailStore` implements it; tests use the real store.
public protocol ThreadFetchStore: PrefetchStore {
    /// Of `threads`, those whose cached bodies don't reach their newest message, or that have none, in their order.
    func threadsMissingBodies(among threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID]
    /// Stores bodies the reader asked for, as read at `accessedAt`.
    func save(_ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date, accessedAt: Date) throws
}

/// Fetches threads' bodies into the store, at most one fetch per thread at a time, so opening a thread joins the
/// fetch its row began when the reader touched it, or when it scrolled into view.
public actor ThreadFetcher {
    /// Why a thread is fetched before it opens.
    public enum ReadAhead: Sendable {
        /// Its row came into view: fetched if the path and the reader's scope allow downloading ahead, a few at a
        /// time, the latest rows first.
        case visible
        /// The reader is touching its row and likely to open it: fetched at once on any connection.
        case touched
    }

    /// What the mail lists ask of the fetcher as their rows show, come up or scroll away.
    public enum Request: Sendable {
        /// Fetches the threads, nearest first, as far as the reason allows.
        case readAhead([ThreadSummary.ID], because: ReadAhead)
        /// The rows scrolled away before their turn: drops them from the queue.
        case skip([ThreadSummary.ID])
    }

    /// Fetches for rows in view running at once.
    public static let visibleConcurrency = 3
    /// Rows in view waiting their turn; a long scroll drops the oldest, which have scrolled away.
    public static let visibleQueueLimit = 24
    private static let log = MailLog(category: "prefetch")

    private enum Kind {
        /// The reader opened it.
        case load
        case readAhead(ReadAhead)
    }

    private let provider: @Sendable (AccountID) throws -> any MailProvider
    private let store: any ThreadFetchStore
    private let path: any NetworkPath
    private let scope: @Sendable () -> PrefetchScope
    private let now: @Sendable () -> Date
    private struct Fetch {
        /// Tells this fetch from one that replaced it after it was cancelled.
        let attempt: UUID
        let task: Task<Void, any Error>
        /// Why it runs now, which decides how its messages are stored when it finishes.
        var kind: Kind
    }

    /// The fetch under way for each thread: a read ahead's failure is dropped, unless a load joined it. A cancelled
    /// fetch leaves at once, though its task may take a while to stop, so it holds neither its thread nor a slot.
    private var fetches: [ThreadSummary.ID: Fetch] = [:]
    /// Rows in view waiting for a fetch, the latest last.
    private var waiting: [ThreadSummary.ID] = []

    public init(
        provider: @escaping @Sendable (AccountID) throws -> any MailProvider,
        store: any ThreadFetchStore,
        path: any NetworkPath,
        scope: @escaping @Sendable () -> PrefetchScope = { .default },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.provider = provider
        self.store = store
        self.path = path
        self.scope = scope
        self.now = now
    }

    /// Fetches the thread's messages into the store as the reader's, or waits for the fetch already under way.
    /// Leaving doesn't stop a fetch others may be waiting on; it finishes and fills the cache.
    public func load(_ thread: ThreadSummary.ID) async throws {
        guard let running = fetches[thread] else {
            return try await start(thread, as: .load).value
        }
        // The reader is waiting on it now, so leaving the foreground no longer cancels it, and it stores the messages
        // as read.
        fetches[thread]?.kind = .load
        try await running.task.value
    }

    public func handle(_ request: Request) {
        switch request {
        case .readAhead(let threads, let reason): readAhead(threads, because: reason)
        case .skip(let threads): skip(threads)
        }
    }

    /// Starts fetching those of `threads` whose bodies are missing, nearest first, as far as `reason` allows, and
    /// returns at once.
    public func readAhead(_ threads: [ThreadSummary.ID], because reason: ReadAhead) {
        let allowed =
            switch reason {
            case .visible: scope().threadLimit(on: path.allowance, unmetered: 1, metered: 1) > 0
            case .touched: path.allowance > .none
            }
        guard allowed else { return }
        let missing: [ThreadSummary.ID]
        do {
            missing = try store.threadsMissingBodies(among: threads.filter { fetches[$0] == nil })
        } catch {
            Self.log.error("The rows missing bodies couldn't be read, so none were fetched ahead", error)
            return
        }
        switch reason {
        case .touched:
            for thread in missing { start(thread, as: .readAhead(.touched)) }
        case .visible:
            waiting.removeAll { missing.contains($0) }
            // The next to start is the last.
            waiting.append(contentsOf: missing.reversed())
            waiting.removeFirst(max(0, waiting.count - Self.visibleQueueLimit))
            startWaiting()
        }
    }

    /// Drops threads waiting their turn, as when their rows scroll away. Fetches already under way go on.
    public func skip(_ threads: [ThreadSummary.ID]) {
        let skipped = Set(threads)
        waiting.removeAll { skipped.contains($0) }
    }

    /// Stops reading ahead, as when the app leaves the foreground. Fetches the reader opened go on.
    ///
    /// A cancelled fetch leaves `fetches` at once and its task is left to stop on its own. That is safe: once
    /// cancelled it stores nothing, since it checks for cancellation on this actor just before it saves, and it can't
    /// remove the fetch that replaced it, which has another `attempt`. What it costs is its one request: the task
    /// ends when the provider answers, gives up, or stops on cancellation as URLSession requests do, and each time
    /// the app leaves the foreground leaves at most one such request per thread.
    public func cancelReadAhead() {
        waiting.removeAll()
        for (thread, fetch) in fetches {
            guard case .readAhead = fetch.kind else { continue }
            fetch.task.cancel()
            fetches[thread] = nil
        }
    }

    /// Waits until no fetch is under way, as after reading ahead to see what was stored. A cancelled fetch stores
    /// nothing, so it isn't waited for.
    public func idle() async {
        while let fetch = fetches.values.first { _ = try? await fetch.task.value }
    }

    /// Whether the reader is waiting on a fetch of the thread now.
    func isJoined(_ thread: ThreadSummary.ID) -> Bool {
        if case .load = fetches[thread]?.kind { true } else { false }
    }

    private var visibleRunning: Int {
        fetches.values.count { if case .readAhead(.visible) = $0.kind { true } else { false } }
    }

    private func startWaiting() {
        while visibleRunning < Self.visibleConcurrency, let thread = waiting.popLast() {
            if fetches[thread] == nil { start(thread, as: .readAhead(.visible)) }
        }
    }

    @discardableResult
    private func start(_ thread: ThreadSummary.ID, as kind: Kind) -> Task<Void, any Error> {
        let attempt = UUID()
        let task = Task {
            defer {
                if fetches[thread]?.attempt == attempt { fetches[thread] = nil }
                startWaiting()
            }
            try await fetch(thread, attempt: attempt)
        }
        fetches[thread] = Fetch(attempt: attempt, task: task, kind: kind)
        return task
    }

    private func fetch(_ thread: ThreadSummary.ID, attempt: UUID) async throws {
        let fetchedAt = now()
        let messages = try await provider(thread.accountID).messages(inThread: thread.threadID)
        try Task.checkCancellation()
        // Not cancelled, so this is still the thread's fetch; a load may have joined it meanwhile.
        guard let fetch = fetches[thread], fetch.attempt == attempt else { return }
        switch fetch.kind {
        case .load: try store.save(messages, inThread: thread, fetchedAt: fetchedAt, accessedAt: now())
        case .readAhead where messages.isEmpty: break
        case .readAhead: try store.savePrefetched(messages, inThread: thread, fetchedAt: fetchedAt)
        }
    }
}
