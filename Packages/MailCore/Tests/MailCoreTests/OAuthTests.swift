import Foundation
import Synchronization
import Testing

@testable import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

struct OAuthTests {
    private let client = OAuthClient(
        name: "example",
        authorizationEndpoint: URL(string: "https://login.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://login.example.com/token")!,
        clientID: "client-1",
        redirectURI: URL(string: "example.app://auth")!,
        scopes: ["Mail.ReadWrite", "offline_access"],
        refreshesWithScopes: true
    )

    @Test func challengeMatchesTheRFC7636Example() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifiersAreUniqueAndWithinRFCLength() {
        let verifiers = Set((0..<100).map { _ in PKCE.generate().verifier })
        #expect(verifiers.count == 100)
        #expect(verifiers.allSatisfy { (43...128).contains($0.count) && !$0.contains("=") })
    }

    @Test func aClientThatRefreshesWithScopesAsksForThemAgain() {
        let fields = client.refreshRequest(refreshToken: "r1").formFields
        #expect(fields["scope"] == "Mail.ReadWrite offline_access")
        #expect(fields["refresh_token"] == "r1")
        #expect(client.redirectScheme == "example.app")
    }

    @Test func theAddressFallsBackToThePreferredUsername() {
        let claims = Data(#"{"preferred_username":"me@outlook.com"}"#.utf8).base64URLEncodedString()
        #expect(OAuthClient.email(fromIDToken: "e30.\(claims).sig") == "me@outlook.com")
    }

    @Test func anIDTokenIsKeptUntilItIsAboutToExpire() async throws {
        let keychain = MemorySecretStore()
        let exp = Int(Date.now.timeIntervalSince1970) + 3600
        let claims = Data(#"{"email":"me@example.com","exp":\#(exp)}"#.utf8).base64URLEncodedString()
        let http = TokenEndpoint(#"{"access_token":"a1","expires_in":3600,"id_token":"e30.\#(claims).sig"}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)

        #expect(try await session.validIDToken() == "e30.\(claims).sig")
    }

    @Test func aServiceThatSendsNoIDTokenSaysSo() async throws {
        let keychain = MemorySecretStore()
        let http = TokenEndpoint(#"{"access_token":"a1","expires_in":3600}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)

        await #expect(throws: OAuthSession.Failure.noIDToken) { try await session.validIDToken() }
    }

    @Test func aRotatedRefreshTokenReplacesTheStoredOne() async throws {
        let keychain = MemorySecretStore()
        let http = TokenEndpoint(#"{"access_token":"a2","expires_in":3600,"refresh_token":"r2"}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)

        #expect(try await session.validAccessToken() == "a2")
        #expect(try keychain.data(for: session.refreshTokenKey) == Data("r2".utf8))
        #expect(session.refreshTokenKey.hasPrefix("example.refresh-token."))
    }
}

/// Answers every request with one token response.
private struct TokenEndpoint: HTTPClient {
    let body: String

    init(_ body: String) {
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private final class MemorySecretStore: SecretStore {
    private let items = Mutex<[String: Data]>([:])

    func data(for key: String) throws -> Data? { items.withLock { $0[key] } }
    func set(_ data: Data, for key: String) throws { items.withLock { $0[key] = data } }
    func remove(_ key: String) throws { _ = items.withLock { $0.removeValue(forKey: key) } }
}

extension URLRequest {
    fileprivate var formFields: [String: String] {
        let query = String(decoding: httpBody ?? Data(), as: UTF8.self)
        let items = URLComponents(string: "?" + query)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
}
