import Foundation
import MailCore
import Synchronization
import Testing

@testable import GmailProvider

/// The relay's metadata grant: its own sign-in, with one scope, whose refresh token goes to the relay.
struct MailboxCheckGrantTests {
    @Test func theGrantAsksForTheMetadataScopeAlone() {
        #expect(OAuthClient.gmailMailboxCheck.scopes == ["https://www.googleapis.com/auth/gmail.metadata"])
        #expect(OAuthClient.gmailMailboxCheck.clientID == OAuthClient.gmail.clientID)
        #expect(OAuthClient.gmailMailboxCheck.name != OAuthClient.gmail.name, "its token never lands in the app's slot")
    }

    @Test func theCodeIsExchangedAndOnlyItsRefreshTokenGoesToTheRelay() async throws {
        let http = FixtureHTTPClient(["/token": [.init(fixture: "token-exchange")]])
        let relay = GrantRecorder()
        try await GmailClient.grantMailboxCheck(code: "code-1", pkce: PKCE.generate(), relay: relay, http: http)
        #expect(http.requests.first?.formFields["code"] == "code-1")
        #expect(relay.granted == ["1//fixture-refresh-token"])
    }
}

private final class GrantRecorder: MailboxCheckRelay {
    private let tokens = Mutex<[String]>([])

    var granted: [String] { tokens.withLock { $0 } }

    func grantMailboxCheck(refreshToken: String) async throws { tokens.withLock { $0.append(refreshToken) } }
    func revokeMailboxCheck(proof: String) async throws {}
    func checksMailbox(proof: String) async throws -> Bool { false }
}
