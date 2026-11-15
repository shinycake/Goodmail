import Foundation
import MailCore
import Testing

@testable import GmailProvider

/// A message read whole, as Forward as Attachment sends it.
struct GmailSourceTests {
    private let keychain = InMemorySecretStore()
    private let message = Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m1")

    private func gmail(_ reply: FixtureHTTPClient.Reply) async throws -> (GmailClient, FixtureHTTPClient) {
        let http = FixtureHTTPClient([
            "/token": [.init(fixture: "token-exchange")], "/gmail/v1/users/me/messages/m1": [reply],
        ])
        let session = try await OAuthSession.signIn(
            client: .gmail, code: "4/abc", pkce: .generate(), http: http, keychain: keychain)
        return (GmailClient(session: session.session, http: http, retryDelays: []), http)
    }

    @Test func theRawMessageDecodesFromBase64URL() async throws {
        let (gmail, http) = try await gmail(.init(fixture: "message-raw"))
        let source = try await gmail.source(of: message)
        #expect(
            String(decoding: source, as: UTF8.self)
                == "From: Dana <dana@example.com>\r\nSubject: =?UTF-8?B?16rXldeb16DXmdeq?=\r\n\r\nShip it??>\r\n")
        let request = try #require(http.requests.last?.url)
        #expect(
            URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems?.contains(
                URLQueryItem(name: "format", value: "raw")) == true)
    }

    @Test func aMessageThatIsGoneIsNotFound() async throws {
        let (gmail, _) = try await gmail(.init(fixture: "not-found", status: 404))
        await #expect(throws: ProviderError.notFound) { try await gmail.source(of: message) }
    }
}
