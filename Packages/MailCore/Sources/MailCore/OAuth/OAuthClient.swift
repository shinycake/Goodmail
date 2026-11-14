import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// A mail service's OAuth 2.0 client for an installed app: authorization code with PKCE, no client secret. Each
/// provider registers one with its service and describes it here.
public struct OAuthClient: Sendable {
    /// Names the service in the Keychain, as in `gmail.refresh-token.<account>`.
    public let name: String
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let clientID: String
    public let redirectURI: URL
    public let scopes: [String]
    /// Whether refreshing asks for the scopes again. Microsoft requires it; Google doesn't need it.
    public let refreshesWithScopes: Bool

    public init(
        name: String,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        clientID: String,
        redirectURI: URL,
        scopes: [String],
        refreshesWithScopes: Bool
    ) {
        self.name = name
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.refreshesWithScopes = refreshesWithScopes
    }

    /// The scheme the sign-in page redirects to, which the web authentication session listens for.
    public var redirectScheme: String { redirectURI.scheme ?? "" }

    public struct Tokens: Sendable, Equatable {
        public let accessToken: String
        public let expiresAt: Date
        /// Present on the first exchange. A refresh may rotate it, and then carries the new one.
        public let refreshToken: String?
        /// The signed-in address, from the ID token. Present on the first exchange only.
        public let email: String?
        /// The ID token itself, which proves the address to a third party such as the push relay. Google sends one
        /// with every exchange and refresh when the client asks for `openid`.
        public let idToken: IDToken?
    }

    /// A signed ID token and when it stops being accepted.
    public struct IDToken: Sendable, Equatable {
        public let value: String
        public let expiresAt: Date
    }

    public enum Failure: Error, Equatable {
        case missingCode
        case stateMismatch
        case tokenEndpoint(status: Int, error: String?)
    }

    public func authorizationURL(pkce: PKCE, state: String, loginHint: String? = nil) -> URL {
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if let loginHint {
            items.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        return authorizationEndpoint.appending(queryItems: items)
    }

    /// The authorization code from the redirect, after checking it answers our request.
    public static func code(fromRedirect url: URL, expectedState: String) throws(Failure) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else { throw .stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw .missingCode }
        return code
    }

    public func exchangeRequest(code: String, pkce: PKCE) -> URLRequest {
        formRequest([
            "client_id": clientID,
            "redirect_uri": redirectURI.absoluteString,
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": pkce.verifier,
        ])
    }

    public func refreshRequest(refreshToken: String) -> URLRequest {
        var fields = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        if refreshesWithScopes { fields["scope"] = scopes.joined(separator: " ") }
        return formRequest(fields)
    }

    public static func tokens(from data: Data, status: Int, receivedAt: Date) throws -> Tokens {
        guard (200..<300).contains(status) else {
            let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw Failure.tokenEndpoint(status: status, error: error?.error)
        }
        let body = try JSONDecoder().decode(TokenBody.self, from: data)
        return Tokens(
            accessToken: body.access_token,
            expiresAt: receivedAt.addingTimeInterval(TimeInterval(body.expires_in)),
            refreshToken: body.refresh_token,
            email: body.id_token.flatMap(email(fromIDToken:)),
            idToken: body.id_token.flatMap(idToken(from:))
        )
    }

    /// Reads the `email` claim, or Microsoft's `preferred_username` when the token leaves `email` out. The token came
    /// straight from the service over TLS, so the signature isn't rechecked.
    static func email(fromIDToken token: String) -> String? {
        guard let claims = claims(of: token) else { return nil }
        return claims.email ?? claims.preferred_username
    }

    /// The token with its `exp` claim, or `nil` when it has none.
    static func idToken(from token: String) -> IDToken? {
        guard let exp = claims(of: token)?.exp else { return nil }
        return IDToken(value: token, expiresAt: Date(timeIntervalSince1970: exp))
    }

    private static func claims(of token: String) -> IDTokenClaims? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let payload = Data(base64URLEncoded: String(parts[1])) else { return nil }
        return try? JSONDecoder().decode(IDTokenClaims.self, from: payload)
    }

    private func formRequest(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return request
    }

    // swift-format-ignore: AlwaysUseLowerCamelCase
    private struct TokenBody: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
        let id_token: String?
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    // swift-format-ignore: AlwaysUseLowerCamelCase
    private struct IDTokenClaims: Decodable {
        let email: String?
        let preferred_username: String?
        let exp: TimeInterval?
    }
}
