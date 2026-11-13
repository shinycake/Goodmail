import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Authorized Microsoft Graph requests for one account, retried when Graph is throttling or briefly down.
struct GraphTransport: Sendable {
    static let baseURL = URL(string: "https://graph.microsoft.com/v1.0/")!

    let session: OAuthSession
    let http: any HTTPClient
    /// The waits before each retry of a throttled or failed request.
    let retryDelays: [Duration]

    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        let url = Self.baseURL.appending(path: path)
        return try await get(query.isEmpty ? url : url.appending(queryItems: query))
    }

    /// A URL Graph handed back whole, such as a page's `@odata.nextLink`.
    func get<Response: Decodable>(_ url: URL) async throws -> Response {
        let data = try await send(url, method: "GET", payload: nil)
        return try JSONDecoder.graph.decode(Response.self, from: data)
    }

    /// Sends `body` as JSON, its keys sorted so a request reads the same every time.
    @discardableResult
    func send(_ url: URL, method: String, json body: some Encodable) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try await send(url, method: method, payload: (try encoder.encode(body), "application/json"))
    }

    /// Which failures a request may be sent again after.
    enum Replay {
        /// Sending it twice ends as sending it once: a read, a patch, a move or a delete.
        case safe
        /// Each send makes something new, such as a sent message or a draft. It is sent again only when Graph turned
        /// it away unread, because after a server error Graph may already have made it.
        case onlyIfRefused
    }

    /// The raw reply, for requests whose answer isn't JSON or isn't read. Only Graph itself is sent the account's
    /// token: a URL that came back from elsewhere, such as a tampered page token, is refused.
    @discardableResult
    func send(
        _ url: URL, method: String, payload: (data: Data, type: String)?, replay: Replay = .safe
    ) async throws -> Data {
        guard url.absoluteString.hasPrefix(Self.baseURL.absoluteString) else { throw ProviderError.rejected }
        var attempt = 0
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(try await session.validAccessToken())", forHTTPHeaderField: "Authorization")
            // IDs that survive a move to another folder, so a moved message keeps its place in the store.
            request.setValue(#"IdType="ImmutableId""#, forHTTPHeaderField: "Prefer")
            if let payload {
                request.setValue(payload.type, forHTTPHeaderField: "Content-Type")
                request.httpBody = payload.data
            }
            let (data, response) = try await http.data(for: request)
            if (200..<300).contains(response.statusCode) { return data }
            let error = GraphError(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
            guard error.allowsRetry(of: replay), attempt < retryDelays.count else { throw error }
            try await Task.sleep(for: Self.wait(after: response, planned: retryDelays[attempt]))
            attempt += 1
        }
    }
}

extension GraphTransport {
    /// The longest a throttled request waits for Graph's `Retry-After` before trying again.
    static let longestWait = Duration.seconds(60)

    /// The planned wait, or longer when Graph says in `Retry-After` how long its throttle lasts.
    static func wait(after response: HTTPURLResponse, planned: Duration) -> Duration {
        guard let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init), seconds > 0 else {
            return planned
        }
        return min(max(planned, .seconds(seconds)), longestWait)
    }
}

public struct GraphError: Error, Equatable {
    public let status: Int
    public let body: String

    /// Whether a request that failed this way may be sent again after a wait. Graph asks clients to retry
    /// throttling and server errors, but only throttling means it did nothing with the request.
    func allowsRetry(of replay: GraphTransport.Replay) -> Bool {
        switch (status, replay) {
        case (429, _): true
        case (500, .safe), (502, .safe), (503, .safe), (504, .safe): true
        default: false
        }
    }
}

extension JSONDecoder {
    /// Graph's dates are ISO 8601, with or without fractional seconds.
    static let graph: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return decoder
    }()
}
