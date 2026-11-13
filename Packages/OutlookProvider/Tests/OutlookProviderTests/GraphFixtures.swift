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

    /// `route` names the fixture for a request, or `nil` for a 404.
    init(_ route: @escaping @Sendable (URLRequest) -> String?) {
        self.route = route
    }

    var requests: [URLRequest] { log.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        guard let name = route(request) else {
            return (Data(#"{"error":{"code":"ErrorItemNotFound"}}"#.utf8), response(request, status: 404))
        }
        return (try fixture(name), response(request, status: 200))
    }

    private func response(_ request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

func fixture(_ name: String) throws -> Data {
    try Data(
        contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
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
