import Foundation
import Testing

@testable import GmailProvider

struct GoogleOAuthTests {
    @Test func challengeMatchesTheRFC7636Example() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifiersAreUniqueAndWithinRFCLength() {
        let verifiers = Set((0..<100).map { _ in PKCE.generate().verifier })
        #expect(verifiers.count == 100)
        #expect(verifiers.allSatisfy { (43...128).contains($0.count) && !$0.contains("=") })
    }

    @Test func authorizationURLAsksForTheCodeWithPKCE() throws {
        let pkce = PKCE(verifier: "verifier")
        let url = GoogleOAuth.authorizationURL(pkce: pkce, state: "s1", loginHint: "a@b.c")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })

        #expect(url.host() == "accounts.google.com")
        #expect(query["response_type"] == "code")
        #expect(query["code_challenge"] == pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["redirect_uri"] == GmailConfiguration.redirectURI.absoluteString)
        #expect(query["state"] == "s1")
        #expect(query["login_hint"] == "a@b.c")
        #expect(query["scope"]??.contains("https://www.googleapis.com/auth/gmail.modify") == true)
    }

    @Test func redirectYieldsTheCodeOnlyForOurState() throws {
        let redirect = URL(string: "\(GmailConfiguration.redirectURI.absoluteString)?state=s1&code=4/abc")!
        #expect(try GoogleOAuth.code(fromRedirect: redirect, expectedState: "s1") == "4/abc")
        #expect(throws: GoogleOAuth.Failure.stateMismatch) {
            try GoogleOAuth.code(fromRedirect: redirect, expectedState: "other")
        }
        let denied = URL(string: "\(GmailConfiguration.redirectURI.absoluteString)?state=s1&error=access_denied")!
        #expect(throws: GoogleOAuth.Failure.missingCode) {
            try GoogleOAuth.code(fromRedirect: denied, expectedState: "s1")
        }
    }

    @Test func exchangeSendsTheVerifierAndNoSecret() {
        let fields = GoogleOAuth.exchangeRequest(code: "4/abc", pkce: PKCE(verifier: "v")).formFields
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["code"] == "4/abc")
        #expect(fields["code_verifier"] == "v")
        #expect(fields["client_secret"] == nil)
    }

    @Test func tokenResponseYieldsTokensExpiryAndEmail() throws {
        let data = try fixture("token-exchange")
        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = try GoogleOAuth.tokens(from: data, status: 200, receivedAt: now)
        #expect(tokens.accessToken == "ya29.fixture-access-token")
        #expect(tokens.refreshToken == "1//fixture-refresh-token")
        #expect(tokens.expiresAt == now.addingTimeInterval(3599))
        #expect(tokens.email == "tester@example.com")
    }

    @Test func revokedGrantIsReportedWithGooglesErrorCode() throws {
        #expect(throws: GoogleOAuth.Failure.tokenEndpoint(status: 400, error: "invalid_grant")) {
            try GoogleOAuth.tokens(from: try fixture("token-invalid-grant"), status: 400, receivedAt: .now)
        }
    }
}

func fixture(_ name: String) throws -> Data {
    try Data(
        contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
}
