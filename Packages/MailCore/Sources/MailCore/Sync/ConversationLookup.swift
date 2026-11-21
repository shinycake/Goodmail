public import Foundation

/// Finds the row of a conversation the reader asked to open, as from a tapped alert that came before sync brought the
/// mail: from the store, or else once from its service, whose answer is stored as sync would store it. It tells a
/// conversation the service says is gone from one it couldn't ask about, as offline, since only the first is gone.
public struct ConversationLookup: Sendable {
    /// What the lookup found.
    public enum Answer: Equatable, Sendable {
        case found(ThreadSummary)
        /// Neither the store nor the service has it, or its account is gone from the device.
        case gone
        /// The store hasn't it and the service couldn't be asked, as offline, or what it answered couldn't be stored.
        case unreachable
    }

    /// Asks the conversation's service for it, as `MailProvider.threads(withIDs:)` does; `nil` when its account has
    /// no service on the device.
    public typealias Fetch = @Sendable (ThreadSummary.ID) async throws -> ThreadFetch?

    private let stored: @Sendable (ThreadSummary.ID) throws -> ThreadSummary?
    private let fetch: Fetch
    private let store: @Sendable (StoreChanges) throws -> Void
    private let now: @Sendable () -> Date

    /// `stored` reads a row from the store, and `store` writes what the service answered.
    public init(
        stored: @escaping @Sendable (ThreadSummary.ID) throws -> ThreadSummary?, fetch: @escaping Fetch,
        store: @escaping @Sendable (StoreChanges) throws -> Void, now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.stored = stored
        self.fetch = fetch
        self.store = store
        self.now = now
    }

    /// Finds `thread`, off the caller's actor, as the store and the service are slow.
    @concurrent public func find(_ thread: ThreadSummary.ID) async -> Answer {
        if let row = try? stored(thread) { return .found(row) }
        let fetchedAt = now()
        let fetched: ThreadFetch
        do {
            guard let answer = try await fetch(thread) else { return .gone }
            fetched = answer
        } catch ProviderError.notFound {
            return .gone
        } catch {
            return .unreachable
        }
        do {
            // Stored as sync stores a change, so the reader's messages have their row to belong to.
            try store(
                StoreChanges(
                    accountID: thread.accountID, upserts: fetched.found, deletions: fetched.missing,
                    fetchedAt: fetchedAt))
        } catch {
            return .unreachable
        }
        guard let row = fetched.found.first(where: { $0.id == thread }) else { return .gone }
        return .found(row)
    }
}
