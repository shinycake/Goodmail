import Foundation
import MailCore
import Synchronization
import Testing

@testable import OutlookProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Answers Graph requests from fixture files, chosen per request by `route`, and records every request.
final class FixtureGraph: HTTPClient {
    private let route: @Sendable (URLRequest) -> String?
    private let log = Mutex<[URLRequest]>([])

    /// `route` names the fixture for a request, `status-<code>` for an error reply, or `nil` for a 404.
    init(_ route: @escaping @Sendable (URLRequest) -> String?) {
        self.route = route
    }

    var requests: [URLRequest] { log.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        guard let name = route(request) else {
            return (Data(#"{"error":{"code":"ErrorItemNotFound"}}"#.utf8), response(request, status: 404))
        }
        if let status = Int(name.trimmingPrefix("status-")), name.hasPrefix("status-") {
            return (Data(#"{"error":{"code":"ErrorInvalidRequest"}}"#.utf8), response(request, status: status))
        }
        return (try fixture(name), response(request, status: 200))
    }

    private func response(_ request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

extension FixtureGraph {
    /// A mailbox with every well-known folder but Conversation History, a user folder at the root and one in the
    /// Inbox, and two conversations in the Inbox.
    static func mailbox(_ request: URLRequest) -> String? {
        let path = request.graphPath
        if request.url!.host() == "login.example.com" { return "token" }
        if let name = path.split(separator: "/").last, path.hasPrefix("me/mailFolders/"),
            let folder = WellKnownFolder(rawValue: String(name)), folder != .conversationhistory
        {
            return "folder-\(name)"
        }
        switch path {
        case "me/mailFolders": return "folders-root"
        case "me/mailFolders/AAInbox/childFolders": return "folders-inbox-children"
        case "me/mailFolders/AAInbox/messages":
            return request.query("$skip") == nil ? "inbox-page1" : "empty-page"
        case "me/mailFolders/AAProjects/childFolders": return "empty-page"
        case "me/messages":
            switch request.query("$filter") {
            case "conversationId eq 'c1'": return "conversation-c1"
            case "conversationId eq 'c2'": return "conversation-c2"
            default: return "empty-page"
            }
        default: return nil
        }
    }
}

/// A file under Fixtures: `name.json`, or the file itself when `name` has an extension, as `m1.eml` does.
func fixture(_ name: String) throws -> Data {
    let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
    let (base, ext) = parts.count == 2 ? (parts[0], parts[1]) : (name, "json")
    return try Data(
        contentsOf: #require(Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures")))
}

extension URLRequest {
    /// The request's path below Graph's version, as in `me/mailFolders/inbox`.
    var graphPath: String { String(url!.path().dropFirst("/v1.0/".count)) }

    func query(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

final class MemorySecretStore: SecretStore {
    private let items = Mutex<[String: Data]>([:])

    func data(for key: String) throws -> Data? { items.withLock { $0[key] } }
    func set(_ data: Data, for key: String) throws { items.withLock { $0[key] = data } }
    func remove(_ key: String) throws { _ = items.withLock { $0.removeValue(forKey: key) } }
}

extension OutlookClient {
    /// A client whose session already holds a token, answering from `graph`.
    static func signedIn(to graph: FixtureGraph) async throws -> OutlookClient {
        let keychain = MemorySecretStore()
        let session = OAuthSession(
            accountID: AccountID(rawValue: "o1"), client: .testing, http: graph, keychain: keychain)
        try keychain.set(Data("refresh".utf8), for: session.refreshTokenKey)
        return OutlookClient(session: session, http: graph, retryDelays: [.zero])
    }
}

extension OAuthClient {
    static let testing = OAuthClient(
        name: "outlook-test",
        authorizationEndpoint: URL(string: "https://login.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://login.example.com/token")!,
        clientID: "test",
        redirectURI: URL(string: "test://auth")!,
        scopes: [],
        refreshesWithScopes: true
    )
}
