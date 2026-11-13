import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// One signed-in Gmail account: keeps a fresh access token, refreshing it from the Keychain's refresh token.
public actor GmailSession {
    public enum Failure: Error, Equatable {
        case signedOut
    }

    public nonisolated let accountID: AccountID
    private let http: any HTTPClient
    private let keychain: any SecretStore
    private var accessToken: (value: String, expiresAt: Date)?
    private var refreshing: Task<String, any Error>?

    public init(accountID: AccountID, http: any HTTPClient = URLSession.shared, keychain: any SecretStore) {
        self.accountID = accountID
        self.http = http
        self.keychain = keychain
    }

    /// Completes sign-in: stores the refresh token and keeps the access token for immediate use.
    /// `accountID` picks the account for the signed-in address, so re-authenticating keeps an account's ID.
    public static func signIn(
        code: String,
        pkce: PKCE,
        accountID: @Sendable (_ email: String) -> AccountID = { _ in .generate() },
        http: any HTTPClient = URLSession.shared,
        keychain: any SecretStore
    ) async throws -> (session: GmailSession, email: String) {
        let (data, response) = try await http.data(for: GoogleOAuth.exchangeRequest(code: code, pkce: pkce))
        let tokens = try GoogleOAuth.tokens(from: data, status: response.statusCode, receivedAt: .now)
        guard let refreshToken = tokens.refreshToken, let email = tokens.email else { throw Failure.signedOut }

        let session = GmailSession(accountID: accountID(email), http: http, keychain: keychain)
        try keychain.set(Data(refreshToken.utf8), for: session.refreshTokenKey)
        await session.remember(tokens)
        return (session, email)
    }

    /// A valid access token, refreshed when it has less than a minute left. Concurrent callers share one refresh.
    public func validAccessToken() async throws -> String {
        if let accessToken, accessToken.expiresAt.timeIntervalSinceNow > 60 {
            return accessToken.value
        }
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
        try keychain.remove(refreshTokenKey)
    }

    nonisolated var refreshTokenKey: String { "gmail.refresh-token.\(accountID.rawValue)" }

    private func refresh() async throws -> String {
        guard let stored = try keychain.data(for: refreshTokenKey) else { throw Failure.signedOut }
        let request = GoogleOAuth.refreshRequest(refreshToken: String(decoding: stored, as: UTF8.self))
        let (data, response) = try await http.data(for: request)
        let tokens = try GoogleOAuth.tokens(from: data, status: response.statusCode, receivedAt: .now)
        remember(tokens)
        return tokens.accessToken
    }

    private func remember(_ tokens: GoogleOAuth.Tokens) {
        accessToken = (tokens.accessToken, tokens.expiresAt)
    }
}
