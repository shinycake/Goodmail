import Foundation
import MailCore
import Synchronization

/// An in-memory mail service with Gmail's sync semantics: a history counter, paged queries, and cursors that
/// expire. Tests change its mail and check that the local store converges.
final class FakeMailServer: MailProvider {
    struct Query: Equatable {
        let query: ThreadQuery
        let pageToken: String?
    }

    private struct State {
        var threads: [String: ThreadSummary] = [:]
        var history = 100
        var changed: [(history: Int, threadID: String)] = []
        var oldestValidCursor = 0
        var failPageRequests: Int?
        var queries: [Query] = []
        var changeRequests = 0
        var performed: [(threadID: String, action: ThreadAction)] = []
        var failPerform: (any Error)?
        var sent: [(raw: Data, threadID: String?)] = []
        var failSend: (any Error)?
        var signature: String? = ""
    }

    let pageSize: Int
    private let state = Mutex(State())

    init(pageSize: Int = 2) {
        self.pageSize = pageSize
    }

    var queries: [Query] { state.withLock { $0.queries } }
    var changeRequests: Int { state.withLock { $0.changeRequests } }

    /// Adds, replaces or (with `nil`) deletes a thread, recording it in history.
    func set(_ id: String, _ thread: ThreadSummary?) {
        state.withLock { state in
            state.threads[id] = thread
            state.history += 1
            state.changed.append((state.history, id))
        }
    }

    /// Forgets history: every earlier cursor expires, as Gmail's do after about a week.
    func expireCursors() {
        state.withLock { $0.oldestValidCursor = $0.history }
    }

    /// Fails the page request after `count` more succeed.
    func failPageRequest(after count: Int) {
        state.withLock { $0.failPageRequests = count }
    }

    func labels() async throws -> [MailLabel] {
        [MailLabel(id: "INBOX", name: "INBOX", kind: .system), MailLabel(id: "Label_1", name: "Receipts", kind: .user)]
    }

    func currentCursor() async throws -> String {
        state.withLock { String($0.history) }
    }

    func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage {
        try state.withLock { state in
            state.queries.append(Query(query: query, pageToken: pageToken))
            if let remaining = state.failPageRequests {
                guard remaining > 0 else { throw URLError(.networkConnectionLost) }
                state.failPageRequests = remaining - 1
            }
            let matching = state.threads.values
                .filter { thread in
                    // Like Gmail, a list without a label leaves Spam and Trash out.
                    (query.label.map { thread.labelIDs.contains($0) }
                        ?? thread.labelIDs.isDisjoint(with: [SystemLabel.spam, SystemLabel.trash]))
                        && (query.since.map { thread.date >= $0 } ?? true)
                        && (query.before.map { thread.date < $0 } ?? true)
                        // Search stands in for Gmail's by matching the subject.
                        && (query.text.map { thread.subject.localizedCaseInsensitiveContains($0) } ?? true)
                }
                .sorted { $0.date > $1.date }
            let start = pageToken.flatMap(Int.init) ?? 0
            let end = min(start + pageSize, matching.count)
            return ThreadPage(
                threads: Array(matching[start..<end]),
                nextPageToken: end < matching.count ? String(end) : nil
            )
        }
    }

    func threads(withIDs ids: [String]) async throws -> ThreadFetch {
        state.withLock { state in
            ThreadFetch(
                found: ids.compactMap { state.threads[$0] },
                missing: ids.filter { state.threads[$0] == nil }
            )
        }
    }

    func changes(since cursor: String) async throws -> ChangeSet {
        try state.withLock { state in
            state.changeRequests += 1
            guard let since = Int(cursor), since >= state.oldestValidCursor else { throw ProviderError.cursorExpired }
            return ChangeSet(
                threadIDs: Set(state.changed.filter { $0.history > since }.map(\.threadID)),
                cursor: String(state.history)
            )
        }
    }

    func messages(inThread threadID: String) async throws -> [Message] { [] }

    func data(for attachment: Attachment, in message: Message.ID) async throws -> Data { Data() }
}

extension FakeMailServer {
    /// Applies an action as Gmail would, recording it in history; a missing thread is `notFound`.
    func perform(_ action: ThreadAction, onThread threadID: String) async throws {
        try state.withLock { state in
            state.performed.append((threadID, action))
            if let failure = state.failPerform { throw failure }
            guard var thread = state.threads[threadID] else { throw ProviderError.notFound }
            var labels = thread.labelIDs
            if thread.isUnread { labels.insert(SystemLabel.unread) }
            labels = action.applied(to: labels)
            thread.isUnread = labels.contains(SystemLabel.unread)
            thread.labelIDs = labels.subtracting([SystemLabel.unread])
            state.threads[threadID] = thread
            state.history += 1
            state.changed.append((state.history, threadID))
        }
    }

    var performed: [(threadID: String, action: ThreadAction)] { state.withLock { $0.performed } }

    /// Makes every `perform` throw `error` until set back to `nil`.
    func failPerform(with error: (any Error)?) {
        state.withLock { $0.failPerform = error }
    }
}

extension FakeMailServer {
    func send(_ raw: Data, inThread threadID: String?) async throws {
        try state.withLock { state in
            if let failure = state.failSend { throw failure }
            state.sent.append((raw, threadID))
        }
    }

    var sent: [(raw: Data, threadID: String?)] { state.withLock { $0.sent } }

    func failSend(with error: (any Error)?) {
        state.withLock { $0.failSend = error }
    }
}

extension FakeMailServer {
    /// Fails like a missing settings scope when `nil`.
    func signature() async throws -> String {
        guard let signature = state.withLock(\.signature) else { throw URLError(.userAuthenticationRequired) }
        return signature
    }

    func setSignature(_ signature: String?) {
        state.withLock { $0.signature = signature }
    }
}
