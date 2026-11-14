import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// One signed-in account at an OAuth service: keeps a fresh access token, refreshing it from the Keychain's refresh
/// token.
public actor OAuthSession {
    public enum Failure: Error, Equatable {
        case signedOut
        /// The service sent no ID token, as when the client doesn't ask for `openid`.
        case noIDToken
    }

    public nonisolated let accountID: AccountID
    public nonisolated let client: OAuthClient
    private let http: any HTTPClient
    private let keychain: any SecretStore
    private var accessToken: (value: String, expiresAt: Date)?
    private var idToken: OAuthClient.IDToken?
    private var refreshing: Task<String, any Error>?

    public init(
        accountID: AccountID,
        client: OAuthClient,
        http: any HTTPClient = URLSession.shared,
        keychain: any SecretStore
    ) {
        self.accountID = accountID
        self.client = client
        self.http = http
        self.keychain = keychain
    }

    /// Completes sign-in: stores the refresh token and keeps the access token for immediate use.
    /// `accountID` picks the account for the signed-in address, so re-authenticating keeps an account's ID.
    public static func signIn(
        client: OAuthClient,
        code: String,
        pkce: PKCE,
        accountID: @Sendable (_ email: String) -> AccountID = { _ in .generate() },
        http: any HTTPClient = URLSession.shared,
        keychain: any SecretStore
    ) async throws -> (session: OAuthSession, email: String) {
        let (data, response) = try await http.data(for: client.exchangeRequest(code: code, pkce: pkce))
        let tokens = try OAuthClient.tokens(from: data, status: response.statusCode, receivedAt: .now)
        guard tokens.refreshToken != nil, let email = tokens.email else { throw Failure.signedOut }

        let session = OAuthSession(accountID: accountID(email), client: client, http: http, keychain: keychain)
        try await session.remember(tokens)
        return (session, email)
    }

    /// A valid access token, refreshed when it has less than a minute left. Concurrent callers share one refresh.
    public func validAccessToken() async throws -> String {
        if let accessToken, accessToken.expiresAt.timeIntervalSinceNow > 60 {
            return accessToken.value
        }
        return try await sharedRefresh()
    }

    /// A valid ID token, refreshed when it has less than five minutes left, so whoever checks it still accepts it.
    public func validIDToken() async throws -> String {
        if let idToken, idToken.expiresAt.timeIntervalSinceNow > 300 {
            return idToken.value
        }
        _ = try await sharedRefresh()
        guard let idToken else { throw Failure.noIDToken }
        return idToken.value
    }

    private func sharedRefresh() async throws -> String {
        if let refreshing {
            return try await refreshing.value
        }
        let task = Task { try await refresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    public func signOut() throws {
        accessToken = nil
        idToken = nil
        try keychain.remove(refreshTokenKey)
    }

    public nonisolated var refreshTokenKey: String { "\(client.name).refresh-token.\(accountID.rawValue)" }

    private func refresh() async throws -> String {
        guard let stored = try keychain.data(for: refreshTokenKey) else { throw Failure.signedOut }
        let request = client.refreshRequest(refreshToken: String(decoding: stored, as: UTF8.self))
        let (data, response) = try await http.data(for: request)
        let tokens = try OAuthClient.tokens(from: data, status: response.statusCode, receivedAt: .now)
        try remember(tokens)
        return tokens.accessToken
    }

    /// Keeps the access token, and stores the refresh token when the service sent one, as a rotating service does.
    private func remember(_ tokens: OAuthClient.Tokens) throws {
        if let refreshToken = tokens.refreshToken {
            try keychain.set(Data(refreshToken.utf8), for: refreshTokenKey)
        }
        accessToken = (tokens.accessToken, tokens.expiresAt)
        // A refresh without one keeps the last, which is still good until it expires.
        if let token = tokens.idToken { idToken = token }
    }
}
