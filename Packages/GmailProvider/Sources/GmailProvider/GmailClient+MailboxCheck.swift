public import MailCore

#if canImport(FoundationNetworking)
    import Foundation
    public import FoundationNetworking  // URLSession on Linux
#else
    public import Foundation
#endif

extension OAuthClient {
    /// The grant the relay checks an account's history with: `gmail.metadata` alone, so it can read labels,
    /// history and headers but never bodies, and can change nothing. Its own sign-in, apart from the app's, so the
    /// app's tokens never carry the metadata scope, which narrows what Gmail lets them do.
    public static let gmailMailboxCheck = OAuthClient(
        name: "gmail-mailbox-check",
        authorizationEndpoint: OAuthClient.gmail.authorizationEndpoint,
        tokenEndpoint: OAuthClient.gmail.tokenEndpoint,
        clientID: OAuthClient.gmail.clientID,
        redirectURI: OAuthClient.gmail.redirectURI,
        scopes: [GmailConfiguration.metadataScope],
        refreshesWithScopes: false
    )
}

extension GmailConfiguration {
    public static let metadataScope = "https://www.googleapis.com/auth/gmail.metadata"
}

extension GmailClient {
    /// Whether the relay holds this account's metadata grant.
    public func checksMailbox(relay: any MailboxCheckRelay) async throws -> Bool {
        try await relay.checksMailbox(proof: try await session.validIDToken())
    }

    /// Has the relay forget this account's metadata grant.
    public func stopMailboxCheck(relay: any MailboxCheckRelay) async throws {
        try await relay.revokeMailboxCheck(proof: try await session.validIDToken())
    }

    /// Exchanges the code from the metadata grant's consent page and hands its refresh token to the relay. The
    /// token isn't kept on the device.
    public static func grantMailboxCheck(
        code: String, pkce: PKCE, relay: any MailboxCheckRelay, http: any HTTPClient = URLSession.shared
    ) async throws {
        let client = OAuthClient.gmailMailboxCheck
        let (data, response) = try await http.data(for: client.exchangeRequest(code: code, pkce: pkce))
        let tokens = try OAuthClient.tokens(from: data, status: response.statusCode, receivedAt: .now)
        guard let refreshToken = tokens.refreshToken else { throw OAuthSession.Failure.signedOut }
        try await relay.grantMailboxCheck(refreshToken: refreshToken)
    }
}
