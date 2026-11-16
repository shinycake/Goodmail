import Foundation
import MailCore
import Testing

@testable import GmailProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct GmailSendAsTests {
    private let keychain = InMemorySecretStore()

    private func client(_ http: FixtureHTTPClient) async throws -> GmailClient {
        let session = try await OAuthSession.signIn(
            client: .gmail, code: "4/abc", pkce: .generate(), http: http, keychain: keychain
        ).session
        return GmailClient(session: session, http: http)
    }

    private static let replies: [String: [FixtureHTTPClient.Reply]] = [
        "/token": [.init(fixture: "token-exchange")],
        "/gmail/v1/users/me/settings/sendAs": [.init(fixture: "send-as")],
        "/gmail/v1/users/me/settings/sendAs/tester@example.com": [.init(fixture: "send-as")],
    ]

    @Test func theSignatureIsTheDefaultAddresssAsPlainText() async throws {
        let sendAs = try await client(FixtureHTTPClient(Self.replies)).sendAs()
        #expect(sendAs.signature == "Dana Levi\nGoodmail & Co.\n\nexample.com")
    }

    @Test func theAliasesAreTheVerifiedOtherAddressesUnderTheirNames() async throws {
        let sendAs = try await client(FixtureHTTPClient(Self.replies)).sendAs()
        #expect(
            sendAs.aliases == [
                Contact(name: "Alias", address: "alias@example.com"),
                Contact(name: nil, address: "unnamed@example.com"),
            ])
    }

    @Test func anEditIsPatchedOntoTheDefaultAddressAsHTML() async throws {
        let http = FixtureHTTPClient(Self.replies)
        try await client(http).setSignature("Dana & Co.\n\n<b>")

        let patch = try #require(http.requests.last)
        #expect(patch.httpMethod == "PATCH")
        #expect(patch.url?.path() == "/gmail/v1/users/me/settings/sendAs/tester@example.com")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(patch.httpBody))
        #expect(
            body == [
                "signature": #"<div dir="auto">Dana &amp; Co.</div><div><br></div><div dir="auto">&lt;b&gt;</div>"#
            ])
    }

    @Test(arguments: ["Dana Levi", "Dana\nGoodmail & Co.\n\nexample.com", "דנה לוי\nGoodmail", ""])
    func theHTMLWrittenReadsBackAsTheSameText(_ text: String) {
        #expect(HTMLEntities.plainText(fromHTML: GmailClient.signatureHTML(text)) == text)
    }
}
