import Foundation
import MailCore
import Testing

@testable import GmailProvider

struct GoogleOAuthTests {
    @Test func authorizationURLAsksForTheCodeWithPKCE() throws {
        let pkce = PKCE(verifier: "verifier")
        let url = OAuthClient.gmail.authorizationURL(pkce: pkce, state: "s1", loginHint: "a@b.c")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })

        #expect(url.host() == "accounts.google.com")
        #expect(query["response_type"] == "code")
        #expect(query["code_challenge"] == pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["redirect_uri"] == OAuthClient.gmail.redirectURI.absoluteString)
        #expect(query["state"] == "s1")
        #expect(query["login_hint"] == "a@b.c")
        #expect(query["scope"]??.contains("https://mail.google.com/") == true, "the full scope, to delete forever")
    }

    @Test func redirectYieldsTheCodeOnlyForOurState() throws {
        let redirect = URL(string: "\(OAuthClient.gmail.redirectURI.absoluteString)?state=s1&code=4/abc")!
        #expect(try OAuthClient.code(fromRedirect: redirect, expectedState: "s1") == "4/abc")
        #expect(throws: OAuthClient.Failure.stateMismatch) {
            try OAuthClient.code(fromRedirect: redirect, expectedState: "other")
        }
        let denied = URL(string: "\(OAuthClient.gmail.redirectURI.absoluteString)?state=s1&error=access_denied")!
        #expect(throws: OAuthClient.Failure.missingCode) {
            try OAuthClient.code(fromRedirect: denied, expectedState: "s1")
        }
    }

    @Test func exchangeSendsTheVerifierAndNoSecret() {
        let fields = OAuthClient.gmail.exchangeRequest(code: "4/abc", pkce: PKCE(verifier: "v")).formFields
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["code"] == "4/abc")
        #expect(fields["code_verifier"] == "v")
        #expect(fields["client_secret"] == nil)
        #expect(OAuthClient.gmail.refreshRequest(refreshToken: "1//r").formFields["scope"] == nil)
    }

    @Test func tokenResponseYieldsTokensExpiryAndEmail() throws {
        let data = try fixture("token-exchange")
        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = try OAuthClient.tokens(from: data, status: 200, receivedAt: now)
        #expect(tokens.accessToken == "ya29.fixture-access-token")
        #expect(tokens.refreshToken == "1//fixture-refresh-token")
        #expect(tokens.expiresAt == now.addingTimeInterval(3599))
        #expect(tokens.email == "tester@example.com")
    }

    @Test func revokedGrantIsReportedWithGooglesErrorCode() throws {
        #expect(throws: OAuthClient.Failure.tokenEndpoint(status: 400, error: "invalid_grant")) {
            try OAuthClient.tokens(from: try fixture("token-invalid-grant"), status: 400, receivedAt: .now)
        }
    }
}

func fixture(_ name: String) throws -> Data {
    try Data(
        contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
}
