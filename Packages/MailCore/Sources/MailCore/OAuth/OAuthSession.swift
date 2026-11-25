#if canImport(FoundationNetworking)
    import Foundation
    public import FoundationNetworking  // URLSession on Linux
#else
    public import Foundation
#endif

/// One signed-in account at an OAuth service: keeps a fresh access token, refreshing it from the Keychain's refresh
/// token, until `end()`.
public actor OAuthSession {
    public enum Failure: Error, Equatable {
        /// No refresh token is stored for the account.
        case signedOut
        /// The session was ended, as once its account signed in afresh or went. Work that meets it was under way on
        /// a sign-in no longer in use, so it says nothing about the account.
        case ended
        /// The service sent no ID token, as when the client doesn't ask for `openid`.
        case noIDToken
    }

    /// What the token responses so far said.
    private struct Grant {
        var accessToken: (value: String, expiresAt: Date)?
        var idToken: OAuthClient.IDToken?
        /// What the last token response granted, or `nil` before one that says.
        var scopes: Set<String>?

        /// A response without an ID token or scopes keeps the last, which are still good until they expire.
        func taking(_ tokens: OAuthClient.Tokens) -> Grant {
            Grant(
                accessToken: (tokens.accessToken, tokens.expiresAt), idToken: tokens.idToken ?? idToken,
                scopes: tokens.scopes ?? scopes)
        }
    }

    private enum State {
        case active(Grant)
        /// One refresh is out, which every caller meanwhile waits for; `last` is kept should it fail.
        case refreshing(Task<Grant, any Error>, last: Grant)
        /// The account was signed out or removed. Nothing is answered, refreshed or written to the Keychain again.
        case ended
    }

    public nonisolated let accountID: AccountID
    public nonisolated let client: OAuthClient
    private let http: any HTTPClient
    private let keychain: any SecretStore
    private var state = State.active(Grant())

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
    /// `endingTheOld` ends the session the account had before its new tokens are stored, so a refresh of the old one
    /// that lands meanwhile can't write its token over the new one.
    public static func signIn(
        client: OAuthClient,
        code: String,
        pkce: PKCE,
        accountID: @Sendable (_ email: String) -> AccountID = { _ in .generate() },
        http: any HTTPClient = URLSession.shared,
        keychain: any SecretStore,
        endingTheOld: @Sendable (AccountID) async -> Void = { _ in }
    ) async throws -> (session: OAuthSession, email: String) {
        let (data, response) = try await http.data(for: client.exchangeRequest(code: code, pkce: pkce))
        let tokens = try OAuthClient.tokens(from: data, status: response.statusCode, receivedAt: .now)
        guard tokens.refreshToken != nil, let email = tokens.email else { throw Failure.signedOut }

        let session = OAuthSession(accountID: accountID(email), client: client, http: http, keychain: keychain)
        await endingTheOld(session.accountID)
        try await session.take(tokens, startingFrom: Grant())
        return (session, email)
    }

    /// A valid access token, refreshed when it has less than a minute left. Concurrent callers share one refresh.
    public func validAccessToken() async throws -> String {
        if let token = try current().accessToken, token.expiresAt.timeIntervalSinceNow > 60 { return token.value }
        guard let token = try await refreshed().accessToken else { throw Failure.signedOut }
        return token.value
    }

    /// A valid ID token, refreshed when it has less than five minutes left, so whoever checks it still accepts it.
    public func validIDToken() async throws -> String {
        if let token = try current().idToken, token.expiresAt.timeIntervalSinceNow > 300 { return token.value }
        guard let token = try await refreshed().idToken else { throw Failure.noIDToken }
        return token.value
    }

    /// Whether the account's sign-in grants `scope`. Refreshes to find out when no token response has said yet;
    /// a service that never says is taken to grant what was asked for.
    public func grants(_ scope: String) async throws -> Bool {
        var scopes = try current().scopes
        if scopes == nil { scopes = try await refreshed().scopes }
        return scopes?.contains(scope) ?? true
    }

    /// Stops using the sign-in, as when its account is removed, and leaves the Keychain to the caller: a refresh
    /// still out is cancelled, and one that answers anyway is dropped, so it never writes its rotated refresh token
    /// back over a removal.
    public func end() {
        if case .refreshing(let task, _) = state { task.cancel() }
        state = .ended
    }

    /// Ends the session and forgets its refresh token in its own Keychain.
    public func signOut() throws {
        end()
        try keychain.remove(refreshTokenKey)
    }

    /// The stored refresh token, for the push relay's look at the mailbox (`PushSource.shareMailbox`).
    public func refreshToken() throws -> String {
        if case .ended = state { throw Failure.ended }
        guard let stored = try keychain.data(for: refreshTokenKey) else { throw Failure.signedOut }
        return String(decoding: stored, as: UTF8.self)
    }

    public nonisolated var refreshTokenKey: String { client.refreshTokenKey(accountID) }

    /// What the session holds now; the last grant while a refresh is out.
    private func current() throws -> Grant {
        switch state {
        case .active(let grant), .refreshing(_, let grant): grant
        case .ended: throw Failure.ended
        }
    }

    /// The grant after a refresh: the one out, or a new one.
    private func refreshed() async throws -> Grant {
        switch state {
        case .ended:
            throw Failure.ended
        case .refreshing(let task, _):
            return try await task.value
        case .active(let last):
            // Runs on this actor, so it can't begin before `state` holds it.
            let task = Task { try await refresh(from: last) }
            state = .refreshing(task, last: last)
            return try await task.value
        }
    }

    /// The refresh itself, which settles `state` however it ends.
    private func refresh(from last: Grant) async throws -> Grant {
        do {
            let request = client.refreshRequest(refreshToken: try refreshToken())
            let (data, response) = try await http.data(for: request)
            let tokens = try OAuthClient.tokens(from: data, status: response.statusCode, receivedAt: .now)
            return try take(tokens, startingFrom: last)
        } catch {
            switch state {
            case .refreshing: state = .active(last)
            // Cancelled by `end()`, which is what the caller should hear.
            case .ended: throw Failure.ended
            case .active: break
            }
            throw error
        }
    }

    /// The one place tokens are kept: stores the refresh token when the service sent one, as a rotating service
    /// does, and moves to the grant they make. Tokens that arrive after `end()` are dropped.
    @discardableResult
    private func take(_ tokens: OAuthClient.Tokens, startingFrom last: Grant) throws -> Grant {
        if case .ended = state { throw Failure.ended }
        if let refreshToken = tokens.refreshToken {
            try keychain.set(Data(refreshToken.utf8), for: refreshTokenKey)
        }
        let grant = last.taking(tokens)
        state = .active(grant)
        return grant
    }
}
