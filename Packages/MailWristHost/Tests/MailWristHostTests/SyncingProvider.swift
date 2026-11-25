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
        var gateIgnoresCancellation = false
        var actionGate: AsyncStream<Void>?
        var actionEntered: AsyncStream<Void>.Continuation?
        var performed: [ThreadAction] = []
        var actionFailure: (any Error)?
        var sent = 0
        var sendFailure: (any Error)?
        var messages: [String: [Message]] = [:]
        /// Set once the service sends by upload: whether its sent mail holds what is asked about.
        var uploadsSent: Bool?
    }

    private let state = Mutex(State())

    init(threads: [ThreadSummary] = []) {
        state.withLock { $0.threads = threads }
    }

    var changeRequests: Int { state.withLock(\.changeRequests) }
    var performed: [ThreadAction] { state.withLock(\.performed) }
    var sent: Int { state.withLock(\.sent) }

    /// Sends by upload from now on, as Gmail does, answering `sent` when asked whether a message went.
    func sendByUpload(sent: Bool) {
        state.withLock { $0.uploadsSent = sent }
    }

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

    /// Holds every "what changed" answer until the returned continuation finishes. Unless `ignoringCancellation`,
    /// a cancelled request stops waiting, as a cancelled `URLSession` request does.
    func holdChanges(ignoringCancellation: Bool = false) -> AsyncStream<Void>.Continuation {
        let (gate, open) = AsyncStream<Void>.makeStream()
        state.withLock {
            $0.gate = gate
            $0.gateIgnoresCancellation = ignoringCancellation
        }
        return open
    }

    /// Holds every action until `open` finishes; `entered` says when one is held.
    func holdActions() -> (entered: AsyncStream<Void>, open: AsyncStream<Void>.Continuation) {
        let (gate, open) = AsyncStream<Void>.makeStream()
        let (entered, enter) = AsyncStream<Void>.makeStream()
        state.withLock {
            $0.actionGate = gate
            $0.actionEntered = enter
        }
        return (entered, open)
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
        let (gate, ignoresCancellation) = state.withLock { state in
            state.changeRequests += 1
            return (state.gate, state.gateIgnoresCancellation)
        }
        if let gate {
            if ignoresCancellation {
                // A task of its own, which cancelling the request doesn't reach.
                await Task { for await _ in gate {} }.value
            } else {
                for await _ in gate {}
            }
        }
        return ChangeSet(threadIDs: [], cursor: cursor)
    }

    func messages(inThread threadID: String) async throws -> [Message] {
        try check()
        return state.withLock { $0.messages[threadID] ?? [] }
    }

    func perform(_ action: ThreadAction, onThread threadID: String) async throws {
        let (gate, entered) = state.withLock { ($0.actionGate, $0.actionEntered) }
        if let gate {
            entered?.yield()
            for await _ in gate {}
        }
        try state.withLock { state in
            if let failure = state.actionFailure { throw failure }
            state.performed.append(action)
        }
    }

    var sending: Sending {
        guard let sent = state.withLock(\.uploadsSent) else { return .direct(Outgoing(provider: self)) }
        return .upload(Uploads(sent: sent))
    }

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

/// Sending by upload, for a test that asks only whether a message went.
private struct Uploads: UploadSending {
    let sent: Bool

    func prepareSend(_ raw: Data, inThread threadID: String?) async throws -> PreparedSend {
        throw URLError(.notConnectedToInternet)
    }

    func answer(status: Int, body: Data) -> SendAnswer { .sent }

    func hasSent(_ message: OutgoingMessage) async throws -> Bool { sent }
}

private struct Outgoing: DirectSending {
    let provider: SyncingProvider

    func send(_ raw: Data, inThread threadID: String?) async throws { try provider.send() }
}
