import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Gmail REST for one account, as a `MailProvider`. Wire types stay in this module; callers get `MailCore` types.
public struct GmailClient: MailProvider, UploadSending {
    let session: OAuthSession
    private let http: any HTTPClient
    private let retryDelays: [Duration]
    private let pageSize: Int

    /// `retryDelays` are the waits before each retry of a rate-limited or failed request.
    public init(
        session: OAuthSession,
        http: any HTTPClient = URLSession.shared,
        retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)],
        pageSize: Int = 50
    ) {
        self.session = session
        self.http = http
        self.retryDelays = retryDelays
        self.pageSize = pageSize
    }

    public func labels() async throws -> [MailLabel] {
        let list: GmailLabelList = try await get("users/me/labels")
        return (list.labels ?? []).map(\.mailLabel)
    }

    public func currentCursor() async throws -> String {
        let profile: GmailProfile = try await get("users/me/profile")
        return profile.historyId
    }

    public func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage {
        var items = [URLQueryItem(name: "maxResults", value: "\(pageSize)")]
        if let label = query.label {
            items.append(URLQueryItem(name: "labelIds", value: label))
            // Gmail leaves Spam and Trash out of lists unless asked.
            if label == SystemLabel.spam || label == SystemLabel.trash {
                items.append(URLQueryItem(name: "includeSpamTrash", value: "true"))
            }
        }
        if let search = query.gmailSearch { items.append(URLQueryItem(name: "q", value: search)) }
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        let list: ThreadList = try await get("users/me/threads", query: items)
        // A thread deleted between the list and the get is simply left out.
        let fetch = try await threads(withIDs: (list.threads ?? []).map(\.id))
        return ThreadPage(threads: fetch.found, nextPageToken: list.nextPageToken)
    }

    public func threads(withIDs ids: [String]) async throws -> ThreadFetch {
        let accountID = session.accountID
        // Fetch headers a few at a time: fast, and well inside Gmail's per-user quota.
        var summaries: [String: ThreadSummary] = [:]
        var missing: Set<String> = []
        for batch in stride(from: 0, to: ids.count, by: 10).map({ Array(ids[$0..<min($0 + 10, ids.count)]) }) {
            try await withThrowingTaskGroup(of: (String, ThreadSummary?).self) { group in
                for id in batch {
                    group.addTask {
                        do {
                            let thread: GmailThread = try await get(
                                "users/me/threads/\(id)",
                                query: [URLQueryItem(name: "format", value: "metadata")]
                                    + ["From", "Subject", "Date"].map {
                                        URLQueryItem(name: "metadataHeaders", value: $0)
                                    }
                            )
                            return (id, thread.summary(accountID: accountID))
                        } catch let error as GmailError where error.status == 404 {
                            return (id, nil)
                        }
                    }
                }
                for try await (id, summary) in group {
                    if let summary { summaries[id] = summary } else { missing.insert(id) }
                }
            }
        }
        return ThreadFetch(found: ids.compactMap { summaries[$0] }, missing: ids.filter(missing.contains))
    }

    public func changes(since cursor: String) async throws -> ChangeSet {
        var threadIDs: Set<String> = []
        var pageToken: String?
        var latest = cursor
        repeat {
            var items = [URLQueryItem(name: "startHistoryId", value: cursor)]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GmailHistoryList
            do {
                page = try await get("users/me/history", query: items)
            } catch let error as GmailError where error.status == 404 {
                throw ProviderError.cursorExpired
            }
            threadIDs.formUnion((page.history ?? []).flatMap(\.threadIDs))
            latest = page.historyId
            pageToken = page.nextPageToken
        } while pageToken != nil
        return ChangeSet(threadIDs: threadIDs, cursor: latest)
    }

    public func messages(inThread threadID: String) async throws -> [Message] {
        let thread: GmailThread = try await get(
            "users/me/threads/\(threadID)", query: [URLQueryItem(name: "format", value: "full")])
        return thread.messages(accountID: session.accountID)
    }

    public func data(for attachment: Attachment, in message: Message.ID) async throws -> Data {
        guard let token = attachment.fetchToken else { throw ProviderError.notFound }
        let body: GmailAttachmentBody
        do {
            body = try await get("users/me/messages/\(message.messageID)/attachments/\(token)")
        } catch let error as GmailError where error.status == 404 {
            throw ProviderError.notFound
        }
        guard let data = Data(base64URLEncoded: body.data) else { throw GmailError(status: 0, body: "Bad base64") }
        return data
    }

    public func perform(_ action: ThreadAction, onThread threadID: String) async throws {
        let path = "users/me/threads/\(threadID)"
        do {
            switch action {
            case .modifyLabels(let add, let remove):
                let body = ["addLabelIds": add.sorted(), "removeLabelIds": remove.sorted()]
                let _: GmailThreadRef = try await send(path + "/modify", method: "POST", body: body)
            case .trash:
                let _: GmailThreadRef = try await send(path + "/trash", method: "POST")
            case .untrash:
                let _: GmailThreadRef = try await send(path + "/untrash", method: "POST")
            case .deleteForever:
                try await deleteTrashedMessages(inThread: path)
            }
        } catch let error as GmailError where error.status == 404 {
            throw ProviderError.notFound
        } catch let error as GmailError where error.status == 400 || error.lacksScope {
            throw ProviderError.rejected
        }
    }

    /// Deletes the thread's messages in Trash for good, one by one, so its messages elsewhere stay. One already gone
    /// is not an error. Needs the full mail scope; an account signed in before Goodmail asked for it is refused.
    private func deleteTrashedMessages(inThread path: String) async throws {
        let thread: GmailThread = try await get(path, query: [URLQueryItem(name: "format", value: "minimal")])
        let trashed = (thread.messages ?? []).filter { $0.labelIds?.contains(SystemLabel.trash) == true }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for message in trashed {
                group.addTask {
                    do {
                        let _: GmailEmpty = try await send("users/me/messages/\(message.id)", method: "DELETE")
                    } catch let error as GmailError where error.status == 404 {
                        return
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    /// Gmail's API takes a send as one upload, which a background session can carry while the app is gone.
    public var sending: Sending { .upload(self) }

    /// Every send goes through the upload endpoint, whatever its size: one request shape, with the message as its
    /// own part, which a background upload can carry from a file.
    public func prepareSend(_ raw: Data, inThread threadID: String?) async throws -> PreparedSend {
        let upload = try Self.multipart(raw, metadata: GmailSendMetadata(threadId: threadID))
        var request = URLRequest(url: Self.uploadURL("users/me/messages/send"))
        request.httpMethod = "POST"
        request.setValue(upload.type, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await session.validAccessToken())", forHTTPHeaderField: "Authorization")
        return PreparedSend(request: request, body: upload.body)
    }

    public func answer(status: Int, body: Data) -> SendAnswer {
        switch status {
        case 200..<300: return .sent
        case 400: return .rejected
        case 404: return .threadGone
        default: break
        }
        switch GmailError(status: status, body: String(decoding: body, as: UTF8.self)).retryable {
        case .throttled: return .turnedAway
        case .serverError: return .unknown
        // An access token that expired while the upload waited to start was turned away unread, and the next
        // upload is prepared with a fresh one. Any other refusal, such as a revoked scope or a message too large,
        // would get the same answer again, so the writer is told.
        case nil: return status == 401 ? .turnedAway : .rejected
        }
    }

    public func hasSent(messageID: String) async throws -> Bool {
        let list: GmailMessageList = try await get(
            "users/me/messages",
            query: [
                URLQueryItem(name: "q", value: "rfc822msgid:\(messageID)"),
                URLQueryItem(name: "labelIds", value: SystemLabel.sent),
                URLQueryItem(name: "includeSpamTrash", value: "true"),
                URLQueryItem(name: "maxResults", value: "1"),
            ])
        return !(list.messages ?? []).isEmpty
    }

    public func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws {
        var draftID: String?
        if let replacing { draftID = try await self.draftID(for: replacing) }
        let path = draftID.map { "users/me/drafts/\($0)" } ?? "users/me/drafts"
        let method = draftID == nil ? "POST" : "PUT"
        // Creating a draft twice leaves two; replacing one twice leaves the same draft.
        let replay: Replay = draftID == nil ? .onlyIfRefused : .safe
        var draft = GmailDraftBody(message: .init(threadId: threadID))
        do {
            if raw.count <= Self.jsonSendLimit {
                draft.message.raw = raw.base64URLEncodedString()
                let _: GmailThreadRef = try await send(path, method: method, body: draft, replay: replay)
            } else {
                let _: GmailThreadRef = try await upload(raw, metadata: draft, to: path, method: method, replay: replay)
            }
        } catch let error as GmailError where error.status == 400 {
            throw ProviderError.rejected
        } catch let error as GmailError where error.status == 404 {
            throw ProviderError.notFound
        }
    }

    public func deleteDraft(_ message: Message.ID) async throws {
        guard let id = try await draftID(for: message) else { return }
        do {
            let _: GmailEmpty = try await send("users/me/drafts/\(id)", method: "DELETE")
        } catch let error as GmailError where error.status == 404 {
            return
        }
    }

    /// Gmail addresses a draft by an ID of its own; this finds the draft holding `message`, if it still exists.
    private func draftID(for message: Message.ID) async throws -> String? {
        var pageToken: String?
        repeat {
            var items = [URLQueryItem(name: "maxResults", value: "500")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GmailDraftList = try await get("users/me/drafts", query: items)
            if let draft = page.drafts?.first(where: { $0.message.id == message.messageID }) { return draft.id }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return nil
    }

    /// The account's contacts and Gmail's "other contacts" (people it wrote to), one entry per address.
    public func contacts() async throws -> [Contact] {
        let saved = try await people("people/me/connections", fields: "personFields", listedIn: \.connections)
        let others = try await people("otherContacts", fields: "readMask", listedIn: \.otherContacts)
        return (saved + others).flatMap(\.contacts)
    }

    /// Every page of one People API list.
    private func people(_ path: String, fields: String, listedIn list: KeyPath<GooglePeoplePage, [GooglePerson]?>)
        async throws -> [GooglePerson]
    {
        var people: [GooglePerson] = []
        var pageToken: String?
        repeat {
            var items = [
                URLQueryItem(name: fields, value: "names,emailAddresses"),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let url = GmailConfiguration.peopleBaseURL.appending(path: path).appending(queryItems: items)
            let page: GooglePeoplePage = try await send(url, method: "GET", payload: nil)
            people += page[keyPath: list] ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return people
    }

    public func signature() async throws -> String {
        let list: GmailSendAsList = try await get("users/me/settings/sendAs")
        let addresses = list.sendAs ?? []
        let sender = addresses.first { $0.isDefault == true } ?? addresses.first { $0.isPrimary == true }
        return HTMLEntities.plainText(fromHTML: sender?.signature ?? "")
    }

    /// Above this many bytes a draft goes through the upload endpoint: as base64 inside JSON it grows by a third,
    /// past what the JSON endpoint takes.
    static let jsonSendLimit = 3_000_000

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await send(path, query: query)
    }

    func send<Response: Decodable>(
        _ path: String, method: String = "GET", query: [URLQueryItem] = [], body: (any Encodable)? = nil,
        replay: Replay = .safe
    ) async throws -> Response {
        let url = GmailConfiguration.apiBaseURL.appending(path: path).appending(queryItems: query)
        return try await send(
            url, method: method, payload: try body.map { (try JSONEncoder().encode($0), "application/json") },
            replay: replay)
    }

    /// A media upload with its JSON metadata, as one `multipart/related` request.
    private func upload<Response: Decodable>(
        _ raw: Data, metadata: some Encodable, to path: String, method: String = "POST", replay: Replay
    ) async throws -> Response {
        let upload = try Self.multipart(raw, metadata: metadata)
        return try await send(Self.uploadURL(path), method: method, payload: (upload.body, upload.type), replay: replay)
    }

    private static func uploadURL(_ path: String) -> URL {
        GmailConfiguration.uploadBaseURL.appending(path: path)
            .appending(queryItems: [URLQueryItem(name: "uploadType", value: "multipart")])
    }

    /// The body of a `multipart/related` upload: the JSON metadata, then the message.
    private static func multipart(_ raw: Data, metadata: some Encodable) throws -> (body: Data, type: String) {
        let boundary = "goodmail-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(try JSONEncoder().encode(metadata))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: message/rfc822\r\n\r\n".utf8))
        body.append(raw)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return (body, "multipart/related; boundary=\(boundary)")
    }

    private func send<Response: Decodable>(
        _ url: URL, method: String, payload: (data: Data, type: String)?, replay: Replay = .safe
    ) async throws -> Response {
        var attempt = 0
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(try await session.validAccessToken())", forHTTPHeaderField: "Authorization")
            if let payload {
                request.setValue(payload.type, forHTTPHeaderField: "Content-Type")
                request.httpBody = payload.data
            }
            let (data, response) = try await http.data(for: request)
            if (200..<300).contains(response.statusCode) {
                if data.isEmpty, let empty = GmailEmpty() as? Response { return empty }
                return try JSONDecoder().decode(Response.self, from: data)
            }
            let error = GmailError(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
            guard replay.allowsRetry(after: error.retryable), attempt < retryDelays.count else { throw error }
            try await Task.sleep(for: retryDelays[attempt])
            attempt += 1
        }
    }
}

/// The addresses the account sends as; Gmail keeps the signature on each.
struct GmailSendAsList: Decodable {
    struct SendAs: Decodable {
        let signature: String?
        let isPrimary: Bool?
        let isDefault: Bool?
    }

    let sendAs: [SendAs]?
}

/// What a sent message's upload says besides the message: the thread it answers.
struct GmailSendMetadata: Encodable {
    let threadId: String?
}

/// One page of `messages.list`; only whether it holds any is read.
struct GmailMessageList: Decodable {
    struct Ref: Decodable {
        let id: String
    }

    let messages: [Ref]?
}

/// A draft to create or replace; Gmail fills in the rest.
struct GmailDraftBody: Encodable {
    struct Message: Encodable {
        var raw: String?
        var threadId: String?
    }

    var message: Message
}

struct GmailDraftList: Decodable {
    struct Draft: Decodable {
        struct Message: Decodable {
            let id: String
        }

        let id: String
        let message: Message
    }

    let drafts: [Draft]?
    let nextPageToken: String?
}

/// One page of `people.connections.list` or `otherContacts.list`.
struct GooglePeoplePage: Decodable {
    let connections: [GooglePerson]?
    let otherContacts: [GooglePerson]?
    let nextPageToken: String?
}

struct GooglePerson: Decodable {
    struct Name: Decodable {
        let displayName: String?
    }

    struct Email: Decodable {
        let value: String?
    }

    let names: [Name]?
    let emailAddresses: [Email]?

    /// One contact per address, all with the person's name.
    var contacts: [Contact] {
        let name = names?.first?.displayName
        return (emailAddresses ?? []).compactMap(\.value).filter { !$0.isEmpty }.map {
            Contact(name: name, address: $0)
        }
    }
}

/// A reply with no body, as `drafts.delete` sends.
struct GmailEmpty: Decodable {}

/// The reply to `threads.modify`, `trash` and `untrash`; only its ID is read.
struct GmailThreadRef: Decodable {
    let id: String
}

public struct GmailError: Error, Equatable {
    public let status: Int
    public let body: String

    /// The token lacks a scope the request needs, as an account signed in before Goodmail asked for it.
    var lacksScope: Bool { status == 403 && body.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") }

    /// Rate limits and server errors, which Google asks clients to retry with exponential backoff.
    var retryable: RetryableFailure? {
        switch status {
        case 429: .throttled
        case 403 where body.contains("rateLimitExceeded") || body.contains("userRateLimitExceeded"): .throttled
        case 500, 502, 503, 504: .serverError
        default: nil
        }
    }
}
