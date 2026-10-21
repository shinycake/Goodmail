import Foundation
import MailCore

/// Gmail REST for one account, as a `MailProvider`. Wire types stay in this module; callers get `MailCore` types.
public struct GmailClient: MailProvider {
    private let session: GmailSession
    private let http: any HTTPClient
    private let retryDelays: [Duration]
    private let pageSize: Int

    /// `retryDelays` are the waits before each retry of a rate-limited or failed request.
    public init(
        session: GmailSession,
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
        if let label = query.label { items.append(URLQueryItem(name: "labelIds", value: label)) }
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
        guard let token = attachment.fetchToken else { throw GmailError(status: 404, body: "No attachment ID") }
        let body: GmailAttachmentBody = try await get("users/me/messages/\(message.messageID)/attachments/\(token)")
        guard let data = Data(base64URLEncoded: body.data) else { throw GmailError(status: 0, body: "Bad base64") }
        return data
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        let url = GmailConfiguration.apiBaseURL.appending(path: path).appending(queryItems: query)
        var attempt = 0
        while true {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(try await session.validAccessToken())", forHTTPHeaderField: "Authorization")
            let (data, response) = try await http.data(for: request)
            if (200..<300).contains(response.statusCode) {
                return try JSONDecoder().decode(Response.self, from: data)
            }
            let error = GmailError(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
            guard error.isTransient, attempt < retryDelays.count else { throw error }
            try await Task.sleep(for: retryDelays[attempt])
            attempt += 1
        }
    }
}

public struct GmailError: Error, Equatable {
    public let status: Int
    public let body: String

    /// Rate limits and server errors, which Google asks clients to retry with exponential backoff.
    var isTransient: Bool {
        switch status {
        case 429, 500, 502, 503, 504: true
        case 403: body.contains("rateLimitExceeded") || body.contains("userRateLimitExceeded")
        default: false
        }
    }
}
