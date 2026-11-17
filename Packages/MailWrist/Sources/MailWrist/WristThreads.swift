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
    /// Fetches a conversation of an account the watch reads itself; `nil` while the watch reads none.
    private let own: (@Sendable (ThreadSummary.ID) async throws -> WristThreadReply)?
    /// The accounts the watch reads itself, as it last decided.
    public var direct: Set<AccountID> = []

    public init(
        patience: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(15)) },
        own: (@Sendable (ThreadSummary.ID) async throws -> WristThreadReply)? = nil
    ) {
        (requests, continuation) = AsyncStream.makeStream(of: ThreadSummary.ID.self)
        self.patience = patience
        self.own = own
    }

    public func state(of id: ThreadSummary.ID) -> Loading {
        threads[id] ?? .loading
    }

    /// Asks the iPhone for the conversation, and waits for the answer: when none has come once `patience` is over,
    /// the iPhone is away. One already loaded stays shown until the new one arrives. Cancelling stops the wait, as
    /// when the reader leaves the conversation or asks again.
    public func load(_ id: ThreadSummary.ID) async {
        if case .loaded = threads[id] {} else { threads[id] = .loading }
        if let own, direct.contains(id.accountID) { return await fetch(id, with: own) }
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
