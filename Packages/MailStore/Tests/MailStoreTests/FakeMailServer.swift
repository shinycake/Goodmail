import Foundation
import MailCore
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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
        var refused: [ThreadAction] = []
        var sent: [(raw: Data, threadID: String?)] = []
        var sendStatus: Int? = 200
        var failPrepare: (any Error)?
        var failLookup: (any Error)?
        var signature: String? = ""
        var contacts: [Contact]? = []
        var contactRequests = 0
        var drafts: [String: (raw: Data, threadID: String?)] = [:]
        var nextDraft = 1
        var messages: [String: [Message]] = [:]
        var messageRequests: [String] = []
        var failMessages: (any Error)?
    }

    /// How the fake takes sends: as Gmail's uploads, or over its own connection, as iCloud's SMTP.
    enum SendPath {
        case upload
        case direct
    }

    let pageSize: Int
    private let sendPath: SendPath
    private let state = Mutex(State())

    init(pageSize: Int = 2, sendPath: SendPath = .upload) {
        self.pageSize = pageSize
        self.sendPath = sendPath
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

    func thread(_ id: String) -> ThreadSummary? {
        state.withLock { $0.threads[id] }
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

    func messages(inThread threadID: String) async throws -> [Message] {
        try state.withLock { state in
            state.messageRequests.append(threadID)
            if let failure = state.failMessages { throw failure }
            return state.messages[threadID] ?? []
        }
    }

    /// The file's ID as its bytes; an attachment without a fetch token is gone.
    func data(for attachment: Attachment, in message: Message.ID) async throws -> Data {
        guard let token = attachment.fetchToken else { throw ProviderError.notFound }
        return Data("\(message.messageID)/\(token)".utf8)
    }
}

extension FakeMailServer {
    /// Applies an action as Gmail would, recording it in history; a missing thread is `notFound`.
    func perform(_ action: ThreadAction, onThread threadID: String) async throws {
        try state.withLock { state in
            state.performed.append((threadID, action))
            if let failure = state.failPerform { throw failure }
            if state.refused.contains(action) { throw ProviderError.rejected }
            guard var thread = state.threads[threadID] else { throw ProviderError.notFound }
            var labels = thread.labelIDs
            if thread.isUnread { labels.insert(SystemLabel.unread) }
            switch action.outcome(for: labels) {
            case .labeled(let labels):
                thread.isUnread = labels.contains(SystemLabel.unread)
                thread.labelIDs = labels.subtracting([SystemLabel.unread])
                state.threads[threadID] = thread
            case .deleted:
                state.threads[threadID] = nil
            }
            state.history += 1
            state.changed.append((state.history, threadID))
        }
    }

    var performed: [(threadID: String, action: ThreadAction)] { state.withLock { $0.performed } }

    /// Makes every `perform` throw `error` until set back to `nil`.
    func failPerform(with error: (any Error)?) {
        state.withLock { $0.failPerform = error }
    }

    /// Makes every `perform` of `action` throw `ProviderError.rejected`, as a service refuses what it won't do.
    func refuse(_ action: ThreadAction) {
        state.withLock { $0.refused.append(action) }
    }
}

extension FakeMailServer: UploadSending {
    var sending: Sending {
        switch sendPath {
        case .upload: .upload(self)
        case .direct: .direct { [self] raw, threadID in try sendDirectly(raw, inThread: threadID) }
        }
    }

    /// A direct send goes, or is refused when `answerSends` set a status outside 2xx.
    private func sendDirectly(_ raw: Data, inThread threadID: String?) throws {
        try state.withLock { state in
            if let failure = state.failPrepare { throw failure }
            guard let status = state.sendStatus, !(200..<300).contains(status) else {
                state.sent.append((raw, threadID))
                return
            }
            throw status == 400 ? ProviderError.rejected : URLError(.badServerResponse)
        }
    }

    func prepareSend(_ raw: Data, inThread threadID: String?) async throws -> PreparedSend {
        try state.withLock { state in
            if let failure = state.failPrepare { throw failure }
            var request = URLRequest(url: URL(string: "https://mail.example/send")!)
            request.setValue(threadID, forHTTPHeaderField: "Thread")
            return PreparedSend(request: request, body: raw)
        }
    }

    func answer(status: Int, body: Data) -> SendAnswer {
        switch status {
        case 200..<300: .sent
        case 400: .rejected
        case 404: .threadGone
        case 500..<600: .unknown
        case 401, 429: .turnedAway
        default: .rejected
        }
    }

    func hasSent(messageID: String) async throws -> Bool {
        try state.withLock { state in
            if let failure = state.failLookup { throw failure }
            return state.sent.contains { String(decoding: $0.raw, as: UTF8.self).contains("<\(messageID)>") }
        }
    }

    /// Takes in an upload the way Gmail would: the message goes, unless `answerSends` says otherwise. With no
    /// answer set, the message goes but the answer is lost, as when the connection drops at the end.
    func receive(_ request: URLRequest, body: Data) -> UploadOutcome {
        state.withLock { state in
            guard let status = state.sendStatus else {
                state.sent.append((body, request.value(forHTTPHeaderField: "Thread")))
                return .noResponse
            }
            if (200..<300).contains(status) { state.sent.append((body, request.value(forHTTPHeaderField: "Thread"))) }
            return .response(status: status, body: Data("{}".utf8))
        }
    }

    var sent: [(raw: Data, threadID: String?)] { state.withLock { $0.sent } }

    /// The status uploads are answered with; `nil` delivers the message but loses the answer.
    func answerSends(with status: Int?) {
        state.withLock { $0.sendStatus = status }
    }

    /// Makes preparing a send throw `error`, as when the token can't be refreshed offline, until set back to `nil`.
    func failPrepare(with error: (any Error)?) {
        state.withLock { $0.failPrepare = error }
    }

    /// Makes `hasSent` throw `error` until set back to `nil`.
    func failLookup(with error: (any Error)?) {
        state.withLock { $0.failLookup = error }
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

extension FakeMailServer {
    /// Keeps drafts by message ID; saving over one gives it a new ID, as Gmail does.
    func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws {
        state.withLock { state in
            if let replacing { state.drafts[replacing.messageID] = nil }
            state.drafts["d\(state.nextDraft)"] = (raw, threadID)
            state.nextDraft += 1
        }
    }

    func deleteDraft(_ message: Message.ID) async throws {
        _ = state.withLock { $0.drafts.removeValue(forKey: message.messageID) }
    }

    var drafts: [String: (raw: Data, threadID: String?)] { state.withLock { $0.drafts } }
}

extension FakeMailServer {
    /// Fails like a People API that isn't enabled when `nil`.
    func contacts() async throws -> [Contact] {
        try state.withLock { state in
            state.contactRequests += 1
            guard let contacts = state.contacts else { throw URLError(.userAuthenticationRequired) }
            return contacts
        }
    }

    func setContacts(_ contacts: [Contact]?) {
        state.withLock { $0.contacts = contacts }
    }

    var contactRequests: Int { state.withLock(\.contactRequests) }
}

extension FakeMailServer {
    /// What `messages(inThread:)` returns for the thread; none until set.
    func setMessages(_ messages: [Message], inThread threadID: String) {
        state.withLock { $0.messages[threadID] = messages }
    }

    /// The threads whose messages were asked for, in order.
    var messageRequests: [String] { state.withLock(\.messageRequests) }

    /// Makes every `messages(inThread:)` throw `error` until set back to `nil`.
    func failMessages(with error: (any Error)?) {
        state.withLock { $0.failMessages = error }
    }
}
