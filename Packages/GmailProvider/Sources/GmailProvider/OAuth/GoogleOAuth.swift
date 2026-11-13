import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Google's OAuth 2.0 endpoints for an installed app: authorization code with PKCE, no client secret.
public enum GoogleOAuth {
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    public struct Tokens: Sendable, Equatable {
        public let accessToken: String
        public let expiresAt: Date
        /// Present on the first exchange only; refreshes reuse the stored one.
        public let refreshToken: String?
        /// The signed-in address, from the ID token. Present on the first exchange only.
        public let email: String?
    }

    public enum Failure: Error, Equatable {
        case missingCode
        case stateMismatch
        case tokenEndpoint(status: Int, error: String?)
    }

    public static func authorizationURL(pkce: PKCE, state: String, loginHint: String? = nil) -> URL {
        var items = [
            URLQueryItem(name: "client_id", value: GmailConfiguration.clientID),
            URLQueryItem(name: "redirect_uri", value: GmailConfiguration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GmailConfiguration.scopes.joined(separator: " ")),
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

    public static func exchangeRequest(code: String, pkce: PKCE) -> URLRequest {
        formRequest([
            "client_id": GmailConfiguration.clientID,
            "redirect_uri": GmailConfiguration.redirectURI.absoluteString,
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": pkce.verifier,
        ])
    }

    public static func refreshRequest(refreshToken: String) -> URLRequest {
        formRequest([
            "client_id": GmailConfiguration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
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
            email: body.id_token.flatMap(email(fromIDToken:))
        )
    }

    /// Reads the `email` claim. The token came straight from Google over TLS, so the signature isn't rechecked.
    static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let payload = Data(base64URLEncoded: String(parts[1])) else { return nil }
        return (try? JSONDecoder().decode(IDTokenClaims.self, from: payload))?.email
    }

    private static func formRequest(_ fields: [String: String]) -> URLRequest {
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

    private struct IDTokenClaims: Decodable {
        let email: String?
    }
}
