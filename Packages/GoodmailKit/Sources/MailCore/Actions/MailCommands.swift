import Foundation

/// The only way to change mail (ADR-011). Applies an action locally at once, queues it for the provider, and returns
/// how to undo it.
public final class MailCommands: Sendable {
    /// What undoes one `perform`: per account, the actions that put each thread back.
    public struct Undo: Equatable, Sendable {
        public var intents: [AccountID: [OutboxIntent]]

        public var isEmpty: Bool { intents.values.allSatisfy(\.isEmpty) }
    }

    private let store: any OutboxStore
    private let replay: @Sendable (AccountID) -> Void
    private let now: @Sendable () -> Date

    /// `replay` is asked to drain an account's outbox after each change.
    public init(
        store: any OutboxStore,
        replay: @escaping @Sendable (AccountID) -> Void,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.replay = replay
        self.now = now
    }

    @discardableResult
    public func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) throws -> Undo {
        var undo = Undo(intents: [:])
        for (account, ids) in Dictionary(grouping: threads, by: \.accountID) {
            let date = now()
            let intents = ids.map { OutboxIntent(threadID: $0.threadID, action: action, createdAt: date) }
            let before = try store.enqueue(intents, account: account)
            undo.intents[account] = ids.flatMap { id in
                before[id.threadID].map { labels in
                    action.inverse(given: labels).map {
                        OutboxIntent(threadID: id.threadID, action: $0, createdAt: date)
                    }
                } ?? []
            }
            replay(account)
        }
        return undo
    }

    public func undo(_ undo: Undo) throws {
        for (account, intents) in undo.intents where !intents.isEmpty {
            let date = now()
            _ = try store.enqueue(
                intents.map { OutboxIntent(threadID: $0.threadID, action: $0.action, createdAt: date) },
                account: account)
            replay(account)
        }
    }
}

/// Sends one account's queued intents to its provider, oldest first.
public actor Outbox {
    public nonisolated let accountID: AccountID
    private let provider: any MailProvider
    private let store: any OutboxStore
    private let now: @Sendable () -> Date
    private var running: Task<Void, any Error>?

    public init(
        accountID: AccountID,
        provider: any MailProvider,
        store: any OutboxStore,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.now = now
    }

    /// Sends everything queued. A thread that is gone, or an intent the provider refuses, drops it; any other failure stops the drain, leaving
    /// the rest queued for the next call. Concurrent callers share the drain in progress.
    public func flush() async throws {
        if let running { return try await running.value }
        let task = Task { try await drain() }
        running = task
        defer { running = nil }
        try await task.value
    }

    private func drain() async throws {
        // Re-read after each send: intents queued meanwhile go out in the same drain.
        while let intent = try store.pendingIntents(for: accountID).first {
            do {
                try await provider.perform(intent.action, onThread: intent.threadID)
                try store.markSent(intent.id, at: now())
            } catch ProviderError.notFound, ProviderError.rejected {
                // Deleted on the server, or refused for good: sending it again changes nothing (ADR-008).
                try store.removeIntent(intent.id)
            }
        }
    }
}
