import Foundation
import MailCore
import Synchronization

/// A service whose Inbox the watch syncs and changes: it lists its threads in one page, records the actions and
/// sends it is given, fails as told, and can hold its answer to "what changed" until the test lets it go.
final class SyncingProvider: MailProvider {
    private struct State {
        var threads: [ThreadSummary] = []
        var failure: (any Error)?
        var changeRequests = 0
        var gate: AsyncStream<Void>?
        var performed: [ThreadAction] = []
        var actionFailure: (any Error)?
        var sent = 0
        var sendFailure: (any Error)?
        var messages: [String: [Message]] = [:]
    }

    private let state = Mutex(State())

    init(threads: [ThreadSummary] = []) {
        state.withLock { $0.threads = threads }
    }

    var changeRequests: Int { state.withLock(\.changeRequests) }
    var performed: [ThreadAction] { state.withLock(\.performed) }
    var sent: Int { state.withLock(\.sent) }

    /// Fails every action with `error` from now on, or stops failing with `nil`.
    func failActions(with error: (any Error)?) {
        state.withLock { $0.actionFailure = error }
    }

    /// Fails every send with `error` from now on, or stops failing with `nil`.
    func failSends(with error: (any Error)?) {
        state.withLock { $0.sendFailure = error }
    }

    func setMessages(_ messages: [Message], inThread threadID: String) {
        state.withLock { $0.messages[threadID] = messages }
    }

    /// Fails every request with `error` from now on, or stops failing with `nil`.
    func fail(with error: (any Error)?) {
        state.withLock { $0.failure = error }
    }

    /// Holds every "what changed" answer until the returned continuation finishes.
    func holdChanges() -> AsyncStream<Void>.Continuation {
        let (gate, open) = AsyncStream<Void>.makeStream()
        state.withLock { $0.gate = gate }
        return open
    }

    private func check() throws {
        if let failure = state.withLock(\.failure) { throw failure }
    }

    func labels() async throws -> [MailLabel] {
        try check()
        return []
    }

    func currentCursor() async throws -> String {
        try check()
        return "1"
    }

    func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage {
        try check()
        let threads = state.withLock { $0.threads }.filter { thread in
            query.label.map { thread.labelIDs.contains($0) } ?? true
        }
        return ThreadPage(threads: threads, nextPageToken: nil)
    }

    func threads(withIDs ids: [String]) async throws -> ThreadFetch {
        try check()
        return ThreadFetch(found: [], missing: [])
    }

    func changes(since cursor: String) async throws -> ChangeSet {
        try check()
        let gate = state.withLock { state in
            state.changeRequests += 1
            return state.gate
        }
        if let gate { for await _ in gate {} }
        return ChangeSet(threadIDs: [], cursor: cursor)
    }

    func messages(inThread threadID: String) async throws -> [Message] {
        try check()
        return state.withLock { $0.messages[threadID] ?? [] }
    }

    func perform(_ action: ThreadAction, onThread threadID: String) async throws {
        try state.withLock { state in
            if let failure = state.actionFailure { throw failure }
            state.performed.append(action)
        }
    }

    var sending: Sending { .direct(Outgoing(provider: self)) }

    fileprivate func send() throws {
        try state.withLock { state in
            if let failure = state.sendFailure { throw failure }
            state.sent += 1
        }
    }

    // Nothing else is asked for.
    func data(for attachment: Attachment, in message: Message.ID) async throws -> Data { Data() }
    func source(of message: Message.ID) async throws -> Data { Data() }
    func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws -> Message.ID? { nil }
    func deleteDraft(_ message: Message.ID) async throws {}
    func contacts() async throws -> [Contact] { [] }
    func createLabel(named name: String) async throws -> MailLabel { throw ProviderError.rejected }
    func renameLabel(_ id: String, to name: String) async throws {}
    func deleteLabel(_ id: String) async throws {}
}

private struct Outgoing: DirectSending {
    let provider: SyncingProvider

    func send(_ raw: Data, inThread threadID: String?) async throws { try provider.send() }
}
