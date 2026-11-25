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

    @Test func theGrantedScopesAreWhatTheServiceSays() async throws {
        let keychain = MemorySecretStore()
        let http = TokenEndpoint(
            #"{"access_token":"a1","expires_in":3600,"scope":"https://www.googleapis.com/auth/gmail.modify openid"}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)

        #expect(try await session.grants("https://www.googleapis.com/auth/gmail.modify"))
        #expect(try await !session.grants("https://mail.google.com/"), "an older sign-in lacks the newer scope")
    }

    @Test func aServiceThatDoesntSayGrantsWhatWasAskedFor() async throws {
        let keychain = MemorySecretStore()
        let http = TokenEndpoint(#"{"access_token":"a1","expires_in":3600}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)

        #expect(try await session.grants("Mail.ReadWrite"))
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

    @Test func signingInAgainEndsTheOldSessionBeforeTheNewTokensAreStored() async throws {
        let keychain = MemorySecretStore()
        let id = AccountID.generate()
        let key = client.refreshTokenKey(id)
        let claims = Data(#"{"email":"me@example.com"}"#.utf8).base64URLEncodedString()
        let http = TokenEndpoint(
            #"{"access_token":"a1","expires_in":3600,"refresh_token":"new","id_token":"e30.\#(claims).sig"}"#)
        let storedWhenEnding = Mutex<Data??>(nil)

        let (session, email) = try await OAuthSession.signIn(
            client: client, code: "c", pkce: .generate(), accountID: { _ in id }, http: http, keychain: keychain,
            endingTheOld: { ended in
                #expect(ended == id)
                let stored = try? keychain.data(for: key)
                storedWhenEnding.withLock { $0 = .some(stored) }
            })

        #expect(email == "me@example.com")
        #expect(session.accountID == id)
        #expect(storedWhenEnding.withLock { $0 } == .some(nil), "an old refresh landing now can't overwrite it")
        #expect(try keychain.data(for: key) == Data("new".utf8))
    }

    @Test func aRefreshThatAnswersAfterTheSessionEndedKeepsNothing() async throws {
        let keychain = MemorySecretStore()
        let http = HeldTokenEndpoint(#"{"access_token":"a2","expires_in":3600,"refresh_token":"r2"}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)

        let refresh = Task { try await session.validAccessToken() }
        await http.requestArrived()
        // The account is removed while the refresh is out: its sign-in goes, then the service answers.
        await session.end()
        try keychain.remove(session.refreshTokenKey)
        http.answer()

        await #expect(throws: OAuthSession.Failure.ended) { try await refresh.value }
        #expect(try keychain.data(for: session.refreshTokenKey) == nil, "the rotated token doesn't bring it back")
    }

    @Test func signingOutDuringARefreshForgetsTheSignInForGood() async throws {
        let keychain = MemorySecretStore()
        let http = HeldTokenEndpoint(#"{"access_token":"a2","expires_in":3600,"refresh_token":"r2"}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)

        let refresh = Task { try await session.validAccessToken() }
        await http.requestArrived()
        try await session.signOut()
        http.answer()

        await #expect(throws: OAuthSession.Failure.ended) { try await refresh.value }
        #expect(try keychain.data(for: session.refreshTokenKey) == nil)
    }

    @Test func anEndedSessionAnswersNothingFromWhatItHad() async throws {
        let keychain = MemorySecretStore()
        let http = TokenEndpoint(#"{"access_token":"a1","expires_in":3600,"scope":"Mail.ReadWrite"}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)
        #expect(try await session.validAccessToken() == "a1")

        await session.end()

        await #expect(throws: OAuthSession.Failure.ended) { try await session.validAccessToken() }
        await #expect(throws: OAuthSession.Failure.ended) { try await session.grants("Mail.ReadWrite") }
        await #expect(throws: OAuthSession.Failure.ended) { try await session.refreshToken() }
        #expect(try keychain.data(for: session.refreshTokenKey) == Data("r1".utf8), "ending leaves the Keychain")
    }

    @Test func aFailedRefreshCanBeTriedAgain() async throws {
        let keychain = MemorySecretStore()
        let http = TokenEndpoint(#"{"access_token":"a1","expires_in":30}"#)
        let session = OAuthSession(accountID: .generate(), client: client, http: http, keychain: keychain)
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)
        // An access token about to expire, so each ask refreshes.
        _ = try await session.validAccessToken()
        try keychain.remove(session.refreshTokenKey)

        await #expect(throws: OAuthSession.Failure.signedOut) { try await session.validAccessToken() }
        try keychain.set(Data("r1".utf8), for: session.refreshTokenKey)
        #expect(try await session.validAccessToken() == "a1", "a refresh can be tried again")
    }
}

/// Holds its one token response until `answer()`, so a test can act while a refresh is out.
private final class HeldTokenEndpoint: HTTPClient {
    private let body: String
    private let arrivals = AsyncStream.makeStream(of: Void.self)
    private let answers = AsyncStream.makeStream(of: Void.self)

    init(_ body: String) {
        self.body = body
    }

    func requestArrived() async {
        var arrivals = arrivals.stream.makeAsyncIterator()
        _ = await arrivals.next()
    }

    func answer() {
        answers.continuation.yield()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        arrivals.continuation.yield()
        // Answers even once the refresh is cancelled, as a response already on its way does.
        var answers = answers.stream.makeAsyncIterator()
        _ = await answers.next()
        return (
            Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
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
