import Foundation
import MailCore

/// Gmail REST calls for one account. Wire types stay in this module; callers get `MailCore` types.
public struct GmailClient: Sendable {
    private let session: GmailSession
    private let http: any HTTPClient

    public init(session: GmailSession, http: any HTTPClient = URLSession.shared) {
        self.session = session
        self.http = http
    }

    /// The newest Inbox threads with their headers, newest first.
    public func inboxThreads(limit: Int = 50) async throws -> [ThreadSummary] {
        let list: ThreadList = try await get(
            "users/me/threads",
            query: [
                URLQueryItem(name: "labelIds", value: "INBOX"), URLQueryItem(name: "maxResults", value: "\(limit)"),
            ]
        )
        let ids = (list.threads ?? []).map(\.id)
        let accountID = session.accountID

        // Fetch headers a few at a time: fast, and well inside Gmail's per-user quota.
        var summaries: [String: ThreadSummary] = [:]
        for batch in stride(from: 0, to: ids.count, by: 10).map({ Array(ids[$0..<min($0 + 10, ids.count)]) }) {
            try await withThrowingTaskGroup(of: ThreadSummary?.self) { group in
                for id in batch {
                    group.addTask {
                        let thread: GmailThread = try await get(
                            "users/me/threads/\(id)",
                            query: [URLQueryItem(name: "format", value: "metadata")]
                                + ["From", "Subject", "Date"].map { URLQueryItem(name: "metadataHeaders", value: $0) }
                        )
                        return thread.summary(accountID: accountID)
                    }
                }
                for try await summary in group {
                    if let summary { summaries[summary.id.threadID] = summary }
                }
            }
        }
        return ids.compactMap { summaries[$0] }
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> Response {
        var request = URLRequest(url: GmailConfiguration.apiBaseURL.appending(path: path).appending(queryItems: query))
        request.setValue("Bearer \(try await session.validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GmailError(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

public struct GmailError: Error, Equatable {
    public let status: Int
    public let body: String
}
