import Foundation
import MailCore
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// An in-memory mail service with Gmail's sync semantics: a history counter, paged queries, and cursors that
/// expire. Tests change its mail and check that the local store converges.
final class FakeMailServer: SendAsSyncing {
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
        var aliases: [Contact] = []
        var signatureWrites: [String] = []
        var failSignatureWrite: (any Error)?
        var onSignatureRead: (@Sendable () async -> Void)?
        var contacts: [Contact]? = []
        var photos: [String: URL] = [:]
        var contactRequests = 0
        var drafts: [String: (raw: Data, threadID: String?)] = [:]
        var nextDraft = 1
        var messages: [String: [Message]] = [:]
        var messageRequests: [String] = []
        var failMessages: (any Error)?
        var onMessagesRequested: (@Sendable (String) async -> Void)?
        var labels = [
            MailLabel(id: "INBOX", name: "INBOX", kind: .system),
            MailLabel(id: "Label_1", name: "Receipts", kind: .user),
        ]
        var nextLabel = 2
        var onLabelsRead: (@Sendable () async -> Void)?
        var onFileSent: (@Sendable () -> Void)?
        var filedSent: [Data] = []
        var preparedSends = 0
    }

    /// How the fake takes sends: as Gmail's uploads, or over its own connection, as iCloud's SMTP.
    enum SendPath {
        case upload
        case direct
    }

    let pageSize: Int
    private let sendPath: SendPath
    private let state = Mutex(State())

    /// The account whose mail it serves, as the IDs it returns say.
    let accountID: AccountID

    init(pageSize: Int = 2, sendPath: SendPath = .upload, accountID: AccountID = AccountID(rawValue: "a")) {
        self.pageSize = pageSize
        self.sendPath = sendPath
        self.accountID = accountID
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

    /// Runs `onLabelsRead` after reading and before answering, as a slow reply would leave room for.
    func labels() async throws -> [MailLabel] {
        let (labels, onRead) = state.withLock { ($0.labels, $0.onLabelsRead) }
        await onRead?()
        return labels
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

    /// Runs `onMessagesRequested` after counting the request and before answering, as a slow reply would.
    func messages(inThread threadID: String) async throws -> [Message] {
        let hook = state.withLock { state in
            state.messageRequests.append(threadID)
            return state.onMessagesRequested
        }
        await hook?(threadID)
        return try state.withLock { state in
            if let failure = state.failMessages { throw failure }
            return state.messages[threadID] ?? []
        }
    }

    /// The file's ID as its bytes; an attachment without a fetch token is gone.
    func data(for attachment: Attachment, in message: Message.ID) async throws -> Data {
        guard let token = attachment.fetchToken else { throw ProviderError.notFound }
        return Data("\(message.messageID)/\(token)".utf8)
    }

    /// A short RFC 5322 message naming the message; one whose ID begins `gone` is gone.
    func source(of message: Message.ID) async throws -> Data {
        guard !message.messageID.hasPrefix("gone") else { throw ProviderError.notFound }
        return Data("Message-ID: <\(message.messageID)@example.com>\r\n\r\nHello\r\n".utf8)
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

extension FakeMailServer {
    var sending: Sending {
        switch sendPath {
        case .upload: .upload(self)
        case .direct: .direct(self)
        }
    }
}

extension FakeMailServer: DirectSending {
    func prepareToSend() async {
        state.withLock { $0.preparedSends += 1 }
    }

    /// How many times a direct send was prepared for.
    var preparedSends: Int { state.withLock { $0.preparedSends } }

    /// A direct send goes, or is refused when `answerSends` set a status outside 2xx.
    func send(_ raw: Data, inThread threadID: String?) async throws {
        try state.withLock { state in
            if let failure = state.failPrepare { throw failure }
            guard let status = state.sendStatus, !(200..<300).contains(status) else {
                state.sent.append((raw, threadID))
                return
            }
            throw status == 400 ? ProviderError.rejected : URLError(.badServerResponse)
        }
    }

    /// Files the copy as an IMAP server that doesn't file its own would, running what `whileFilingSent` was given first.
    func fileSent(_ raw: Data, inThread threadID: String?) async {
        let hook = state.withLock { $0.onFileSent }
        hook?()
        state.withLock { $0.filedSent.append(raw) }
    }

    /// Copies of direct sends filed in Sent.
    var filedSent: [Data] { state.withLock { $0.filedSent } }

    /// Runs `body` as each copy of a direct send is filed, to see what the queue holds then.
    func whileFilingSent(_ body: @escaping @Sendable () -> Void) {
        state.withLock { $0.onFileSent = body }
    }
}

extension FakeMailServer: UploadSending {
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

    func hasSent(_ message: OutgoingMessage) async throws -> Bool {
        try state.withLock { state in
            if let failure = state.failLookup { throw failure }
            return state.sent.contains { String(decoding: $0.raw, as: UTF8.self).contains("<\(message.headerID)>") }
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
    /// Fails like a missing settings scope when the signature is `nil`. Runs `onSignatureRead` after reading and before answering,
    /// as a slow reply would leave room for.
    func sendAs() async throws -> SendAs {
        let (signature, aliases, onRead) = state.withLock { ($0.signature, $0.aliases, $0.onSignatureRead) }
        await onRead?()
        guard let signature else { throw URLError(.userAuthenticationRequired) }
        return SendAs(signature: signature, aliases: aliases)
    }

    func setSignature(_ text: String) async throws {
        try state.withLock { state in
            if let error = state.failSignatureWrite { throw error }
            state.signature = text
            state.signatureWrites.append(text)
        }
    }

    /// The signature `sendAs()` answers from now on; `nil` makes it fail.
    func serveSignature(_ signature: String?) {
        state.withLock { $0.signature = signature }
    }

    /// The aliases `sendAs()` answers from now on.
    func serveAliases(_ aliases: [Contact]) {
        state.withLock { $0.aliases = aliases }
    }

    /// The signatures written to the server, oldest first.
    var signatureWrites: [String] { state.withLock(\.signatureWrites) }

    /// Makes writing the signature throw `error` until set back to `nil`.
    func failSignatureWrite(with error: (any Error)?) {
        state.withLock { $0.failSignatureWrite = error }
    }

    /// Runs `hook` during every signature read, until set back to `nil`.
    func onSignatureRead(_ hook: (@Sendable () async -> Void)?) {
        state.withLock { $0.onSignatureRead = hook }
    }
}

extension FakeMailServer {
    /// Keeps drafts by message ID; saving over one gives it a new ID, as Gmail does.
    func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws -> Message.ID? {
        let id = state.withLock { state in
            if let replacing { state.drafts[replacing.messageID] = nil }
            let id = "d\(state.nextDraft)"
            state.drafts[id] = (raw, threadID)
            state.nextDraft += 1
            return id
        }
        return Message.ID(accountID: accountID, messageID: id)
    }

    func deleteDraft(_ message: Message.ID) async throws {
        _ = state.withLock { $0.drafts.removeValue(forKey: message.messageID) }
    }

    var drafts: [String: (raw: Data, threadID: String?)] { state.withLock { $0.drafts } }
}

extension FakeMailServer: ContactPhotoSyncing {
    func contactsWithPhotos() async throws -> (contacts: [Contact], photos: [String: URL]) {
        let contacts = try await contacts()
        return (contacts, state.withLock { $0.photos })
    }

    /// Fails like a People API that isn't enabled when `nil`.
    func contacts() async throws -> [Contact] {
        try state.withLock { state in
            state.contactRequests += 1
            guard let contacts = state.contacts else { throw URLError(.userAuthenticationRequired) }
            return contacts
        }
    }

    func setContacts(_ contacts: [Contact]?, photos: [String: URL] = [:]) {
        state.withLock {
            $0.contacts = contacts
            $0.photos = photos
        }
    }

    var contactRequests: Int { state.withLock(\.contactRequests) }
}

extension FakeMailServer {
    /// What `messages(inThread:)` returns for the thread; none until set.
    func setMessages(_ messages: [Message], inThread threadID: String) {
        state.withLock { $0.messages[threadID] = messages }
    }

    /// Adds a message to what `messages(inThread:)` returns for the thread.
    func append(_ message: Message, inThread threadID: String) {
        state.withLock { $0.messages[threadID, default: []].append(message) }
    }

    /// The threads whose messages were asked for, in order.
    var messageRequests: [String] { state.withLock(\.messageRequests) }

    /// Makes every `messages(inThread:)` throw `error` until set back to `nil`.
    func failMessages(with error: (any Error)?) {
        state.withLock { $0.failMessages = error }
    }
}

/// User labels as Gmail keeps them: a taken name is refused, and a deleted label leaves its threads without recording
/// them in history.
extension FakeMailServer {
    func createLabel(named name: String) async throws -> MailLabel {
        try state.withLock { state in
            guard !state.labels.contains(where: { $0.name == name }) else { throw ProviderError.rejected }
            let label = MailLabel(id: "Label_\(state.nextLabel)", name: name, kind: .user)
            state.nextLabel += 1
            state.labels.append(label)
            return label
        }
    }

    func renameLabel(_ id: String, to name: String) async throws {
        try state.withLock { state in
            guard let old = state.labels.first(where: { $0.id == id })?.name else { throw ProviderError.notFound }
            guard !state.labels.contains(where: { $0.name == name && $0.id != id }) else {
                throw ProviderError.rejected
            }
            // With the labels nested in it, as every service's renameLabel does.
            for index in state.labels.indices where state.labels[index].name.hasPrefix(old + "/") {
                state.labels[index].name = name + state.labels[index].name.dropFirst(old.count)
            }
            if let index = state.labels.firstIndex(where: { $0.id == id }) { state.labels[index].name = name }
        }
    }

    func deleteLabel(_ id: String) async throws {
        state.withLock { state in
            // With the labels nested in it, as every service's deleteLabel does.
            guard let name = state.labels.first(where: { $0.id == id })?.name else { return }
            let doomed = Set(state.labels.filter { $0.id == id || $0.name.hasPrefix(name + "/") }.map(\.id))
            state.labels.removeAll { doomed.contains($0.id) }
            for (threadID, thread) in state.threads where !thread.labelIDs.isDisjoint(with: doomed) {
                state.threads[threadID]?.labelIDs.subtract(doomed)
            }
        }
    }

    func onMessagesRequested(_ hook: (@Sendable (String) async -> Void)?) {
        state.withLock { $0.onMessagesRequested = hook }
    }

    func onLabelsRead(_ hook: (@Sendable () async -> Void)?) {
        state.withLock { $0.onLabelsRead = hook }
    }
}
