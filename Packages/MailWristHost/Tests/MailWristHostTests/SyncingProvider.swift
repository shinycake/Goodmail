import Foundation
import MailCore
import Synchronization

/// A service whose Inbox the watch syncs: it lists its threads in one page, fails as told, and can hold its answer
/// to "what changed" until the test lets it go.
final class SyncingProvider: MailProvider {
    private struct State {
        var threads: [ThreadSummary] = []
        var failure: (any Error)?
        var changeRequests = 0
        var gate: AsyncStream<Void>?
    }

    private let state = Mutex(State())

    init(threads: [ThreadSummary] = []) {
        state.withLock { $0.threads = threads }
    }

    var changeRequests: Int { state.withLock(\.changeRequests) }

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

    // Syncing needs nothing else.
    func messages(inThread threadID: String) async throws -> [Message] { [] }
    func data(for attachment: Attachment, in message: Message.ID) async throws -> Data { Data() }
    func source(of message: Message.ID) async throws -> Data { Data() }
    func perform(_ action: ThreadAction, onThread threadID: String) async throws {}
    var sending: Sending { .direct(Unsent()) }
    func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws -> Message.ID? { nil }
    func deleteDraft(_ message: Message.ID) async throws {}
    func contacts() async throws -> [Contact] { [] }
    func createLabel(named name: String) async throws -> MailLabel { throw ProviderError.rejected }
    func renameLabel(_ id: String, to name: String) async throws {}
    func deleteLabel(_ id: String) async throws {}
}

private struct Unsent: DirectSending {
    func send(_ raw: Data, inThread threadID: String?) async throws {}
}
