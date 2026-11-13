import Foundation

/// The only way to change mail (ADR-011). Applies an action locally at once, queues it for the provider, and returns
/// how to undo it.
///
/// An actor, so a command's reads and writes never interleave with another's and never run on the main actor: a
/// write can wait out another process's lock on the database (ADR-002).
public actor MailCommands {
    /// Everything the commands change.
    public typealias Store = OutboxStore & OutgoingStore & SnoozeStore

    /// What undoes one `perform` or `snooze`: per account, the actions that put each thread back, and each snoozed
    /// thread's snooze from before (`nil` for none).
    public struct Undo: Equatable, Sendable {
        public var intents: [AccountID: [OutboxIntent]]
        public var snoozes: [ThreadSummary.ID: SnoozeState?] = [:]

        public var isEmpty: Bool { intents.values.allSatisfy(\.isEmpty) && snoozes.isEmpty }
    }

    private let store: any Store
    private let replay: @Sendable (AccountID) -> Void
    private let deliver: @Sendable (AccountID, Date) -> Void
    private let now: @Sendable () -> Date

    /// `replay` is asked to drain an account's outbox after each change; `deliver` to send its queued messages
    /// once the given date passes.
    public init(
        store: any Store,
        replay: @escaping @Sendable (AccountID) -> Void,
        deliver: @escaping @Sendable (AccountID, Date) -> Void = { _, _ in },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.replay = replay
        self.deliver = deliver
        self.now = now
    }

    /// Queues `draft` to send once `delay` passes; until then `cancelSend` takes it back.
    public func send(_ draft: Draft, after delay: Duration) throws {
        let sendAt = now().addingTimeInterval(Double(delay.components.seconds))
        try store.enqueue(OutgoingMessage(draft: draft, sendAt: sendAt))
        deliver(draft.accountID, sendAt)
    }

    /// Queues `draft` to send at `date`. It waits, listed under Scheduled, until then; `cancelSend` takes it back.
    public func schedule(_ draft: Draft, at date: Date) throws {
        try store.enqueue(OutgoingMessage(draft: draft, purpose: .scheduledSend, sendAt: date))
        deliver(draft.accountID, date)
    }

    /// Takes a scheduled message out of the queue and keeps it in the provider's Drafts instead.
    /// One write turns it into a draft save, so a failure can't leave it in neither place.
    public func unschedule(_ id: Draft.ID) throws {
        let date = now()
        guard let message = try store.requeue(id, as: .saveDraft, at: date) else { return }
        deliver(message.draft.accountID, date)
    }

    /// Takes back a queued message that hasn't gone yet, returning its draft to edit. `nil` once it has gone.
    public func cancelSend(_ id: Draft.ID) throws -> Draft? {
        try store.cancel(id)?.draft
    }

    /// Saves `draft` with the provider, replacing the copy it was opened from.
    public func saveDraft(_ draft: Draft) throws {
        try enqueueNow(draft, purpose: .saveDraft)
    }

    /// Removes the provider's copy of a draft opened from it. A draft never saved needs nothing.
    public func deleteDraft(_ draft: Draft) throws {
        guard draft.savedDraft != nil else { return }
        try enqueueNow(draft, purpose: .deleteDraft)
    }

    /// Tries a message that failed again, now, for the same purpose.
    public func retrySend(_ message: OutgoingMessage) throws {
        try store.remove(message.id)
        try enqueueNow(message.draft, purpose: message.purpose)
    }

    private func enqueueNow(_ draft: Draft, purpose: OutgoingMessage.Purpose) throws {
        let date = now()
        try store.enqueue(OutgoingMessage(draft: draft, purpose: purpose, sendAt: date))
        deliver(draft.accountID, date)
    }

    /// Forgets a message that failed to send.
    public func discardSend(_ id: Draft.ID) throws {
        try store.remove(id)
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

    /// Takes the threads out of the Inbox until `date`, when `wakeSnoozed` puts them back.
    @discardableResult
    public func snooze(_ threads: [ThreadSummary.ID], until date: Date) throws -> Undo {
        let before = try store.snoozes(of: threads)
        var undo = try perform(.archive, on: threads)
        undo.snoozes = Dictionary(uniqueKeysWithValues: threads.map { ($0, before[$0]) })
        try store.setSnoozes(Dictionary(uniqueKeysWithValues: threads.map { ($0, .asleep(until: date)) }))
        return undo
    }

    /// Puts snoozed threads back in the Inbox now and ends their snooze; undo snoozes them again.
    @discardableResult
    public func unsnooze(_ threads: [ThreadSummary.ID]) throws -> Undo {
        let before = try store.snoozes(of: threads)
        var undo = try perform(.moveToInbox, on: threads)
        undo.snoozes = Dictionary(uniqueKeysWithValues: threads.map { ($0, before[$0]) })
        try store.setSnoozes(Dictionary(uniqueKeysWithValues: threads.map { ($0, nil) }))
        return undo
    }

    /// Puts back in the Inbox, unread, every thread whose snooze is over, then forgets snoozes that are done.
    /// Returns the threads it woke.
    @discardableResult
    public func wakeSnoozed() throws -> [ThreadSummary.ID] {
        let date = now()
        try store.pruneSnoozes(at: date)
        let due = try store.dueSnoozes(by: date)
        guard !due.isEmpty else { return [] }
        try perform(.modifyLabels(add: [SystemLabel.inbox, SystemLabel.unread], remove: []), on: due)
        try store.setSnoozes(Dictionary(uniqueKeysWithValues: due.map { ($0, .woke(at: date)) }))
        return due
    }

    /// Puts the labels back before the snoozes, so a snooze restored as asleep never meets its thread still in the
    /// Inbox, which would end it.
    public func undo(_ undo: Undo) throws {
        for (account, intents) in undo.intents where !intents.isEmpty {
            let date = now()
            _ = try store.enqueue(
                intents.map { OutboxIntent(threadID: $0.threadID, action: $0.action, createdAt: date) },
                account: account)
            replay(account)
        }
        if !undo.snoozes.isEmpty { try store.setSnoozes(undo.snoozes) }
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
