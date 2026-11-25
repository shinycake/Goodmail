public import MailCore
public import Observation

/// The conversations the watch has opened: each one's state, kept so reopening one shows it at once while it is
/// fetched again. A conversation of an account the watch reads itself comes from its own host; any other from the
/// iPhone (ADR-023).
@MainActor @Observable
public final class WristThreads {
    public enum Loading: Equatable, Sendable {
        case loading
        case loaded(WristThread)
        /// The iPhone isn't reachable, or didn't answer in time.
        case phoneAway
        /// The iPhone no longer has it.
        case gone
        /// The watch couldn't fetch it from the account's service.
        case failed(FailureReason)
    }

    private var threads: [ThreadSummary.ID: Loading] = [:]
    /// The conversations to ask the iPhone for, in order, for `WristLink` to send.
    public nonisolated let requests: AsyncStream<ThreadSummary.ID>
    private let continuation: AsyncStream<ThreadSummary.ID>.Continuation
    /// How long to wait for the iPhone's answer before saying it didn't come. Throws when the wait is cancelled.
    private let patience: @Sendable () async throws -> Void
    /// Where conversations come from. Only `readDirectly` changes it.
    public private(set) var fetching: Fetching

    /// Where the watch fetches conversations from (ADR-023).
    public enum Fetching: Sendable {
        /// From the iPhone only, until the watch's own host has said which accounts it reads, or when it can't open.
        case phoneOnly
        /// The conversations of the `direct` accounts from the watch's own host with `fetch`; the rest from the
        /// iPhone. They come together, since the host decides the accounts.
        case own(fetch: @Sendable (ThreadSummary.ID) async throws -> WristThreadReply, direct: Set<AccountID>)
    }

    public init(
        patience: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(15)) },
        fetching: Fetching = .phoneOnly
    ) {
        (requests, continuation) = AsyncStream.makeStream(of: ThreadSummary.ID.self)
        self.patience = patience
        self.fetching = fetching
    }

    /// The watch's own host decided which accounts it reads itself: their conversations come from it, with `fetch`.
    /// The same accounts again change nothing, so the screens showing them aren't redrawn for each snapshot: every
    /// `fetch` asks the same host.
    public func readDirectly(
        _ accounts: Set<AccountID>, with fetch: @escaping @Sendable (ThreadSummary.ID) async throws -> WristThreadReply
    ) {
        if case .own(_, let direct) = fetching, direct == accounts { return }
        fetching = .own(fetch: fetch, direct: accounts)
    }

    /// Whether the watch's own host fetches the conversations of `account`, rather than the iPhone.
    public func readsItself(_ account: AccountID) -> Bool {
        ownFetch(for: account) != nil
    }

    private func ownFetch(for account: AccountID) -> (@Sendable (ThreadSummary.ID) async throws -> WristThreadReply)? {
        guard case .own(let fetch, let direct) = fetching, direct.contains(account) else { return nil }
        return fetch
    }

    public func state(of id: ThreadSummary.ID) -> Loading {
        threads[id] ?? .loading
    }

    /// Asks the iPhone for the conversation, and waits for the answer: when none has come once `patience` is over,
    /// the iPhone is away. One already loaded stays shown until the new one arrives. Cancelling stops the wait, as
    /// when the reader leaves the conversation or asks again.
    public func load(_ id: ThreadSummary.ID) async {
        if case .loaded = threads[id] {} else { threads[id] = .loading }
        if let own = ownFetch(for: id.accountID) { return await fetch(id, with: own) }
        continuation.yield(id)
        do {
            try await patience()
        } catch {
            return
        }
        phoneIsAway(id)
    }

    /// Fetches the conversation from the watch's own host. A failure keeps one loaded before shown.
    private func fetch(
        _ id: ThreadSummary.ID, with own: @Sendable (ThreadSummary.ID) async throws -> WristThreadReply
    ) async {
        do {
            receive(try await own(id))
        } catch is CancellationError {
            return
        } catch {
            if case .loaded = state(of: id) { return }
            threads[id] = .failed(FailureReason(error))
        }
    }

    public func receive(_ reply: WristThreadReply) {
        switch reply {
        case .thread(let thread): threads[thread.id] = .loaded(thread)
        case .gone(let id): threads[id] = .gone
        }
    }

    /// The iPhone can't answer. A conversation loaded before stays shown.
    public func phoneIsAway(_ id: ThreadSummary.ID) {
        if case .loading = state(of: id) { threads[id] = .phoneAway }
    }
}
