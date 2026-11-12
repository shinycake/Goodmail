import Foundation
import MailCore
import Testing

@testable import GmailProvider

struct GmailClientTests {
    private let keychain = InMemorySecretStore()

    private func signedIn(_ http: FixtureHTTPClient) async throws -> GmailSession {
        try await GmailSession.signIn(code: "4/abc", pkce: .generate(), http: http, keychain: keychain).session
    }

    private static let inboxReplies: [String: [FixtureHTTPClient.Reply]] = [
        "/token": [.init(fixture: "token-exchange"), .init(fixture: "token-refresh")],
        "/gmail/v1/users/me/threads": [.init(fixture: "threads-inbox")],
        "/gmail/v1/users/me/threads/18f0a1": [.init(fixture: "thread-18f0a1")],
        "/gmail/v1/users/me/threads/18f0a2": [.init(fixture: "thread-18f0a2")],
        "/gmail/v1/users/me/threads/18f0a3": [.init(fixture: "thread-18f0a3")],
    ]

    @Test func inboxThreadsKeepGmailsOrderAndMapToSummaries() async throws {
        let http = FixtureHTTPClient(Self.inboxReplies)
        let session = try await signedIn(http)
        let threads = try await GmailClient(session: session, http: http).threads(
            matching: ThreadQuery(label: "INBOX"), pageToken: nil
        ).threads

        #expect(threads.map(\.id.threadID) == ["18f0a1", "18f0a2", "18f0a3"])
        #expect(threads.allSatisfy { $0.id.accountID == session.accountID })

        let lunch = threads[0]
        #expect(lunch.subject == "Lunch", "the subject comes from the first message")
        #expect(lunch.sender == Contact(name: "Dana Levi", address: "dana@example.com"), "the latest sender")
        #expect(lunch.snippet == "Sure \u{2014} let's do 12:30 at Dana&Co. \"Same table\"")
        #expect(lunch.date == Date(timeIntervalSince1970: 1_792_501_200))
        #expect(lunch.isUnread)
        #expect(lunch.messageCount == 2)
        #expect(lunch.labelIDs == ["INBOX", "CATEGORY_PERSONAL", "IMPORTANT"])

        let hebrew = threads[1]
        #expect(hebrew.sender == Contact(name: "יעל כהן", address: "yael@example.co.il"))
        #expect(hebrew.subject == "סיכום פגישה")
        #expect(!hebrew.isUnread)

        let bare = threads[2]
        #expect(bare.sender == Contact(name: nil, address: "noreply@shop.example"))
        #expect(bare.subject == "")
    }

    @Test func requestsAskForMetadataHeadersWithTheBearerToken() async throws {
        let http = FixtureHTTPClient(Self.inboxReplies)
        _ = try await GmailClient(session: try await signedIn(http), http: http)
            .threads(matching: ThreadQuery(label: "INBOX"), pageToken: nil)

        let threadGet = try #require(http.requests.first { $0.url!.path().hasSuffix("/threads/18f0a1") })
        let query = try #require(threadGet.url?.query())
        #expect(query.contains("format=metadata"))
        #expect(query.contains("metadataHeaders=Subject"))
        #expect(threadGet.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.fixture-access-token")

        let list = try #require(http.requests.first { $0.url!.path().hasSuffix("/threads") })
        #expect(list.url?.query()?.contains("labelIds=INBOX") == true)
    }

    @Test func expiredAccessTokenIsRefreshedOnceForConcurrentCallers() async throws {
        let http = FixtureHTTPClient(["/token": [.init(fixture: "token-refresh")]])
        let session = GmailSession(accountID: .generate(), http: http, keychain: keychain)
        try keychain.set(Data("1//stored".utf8), for: session.refreshTokenKey)

        async let first = session.validAccessToken()
        async let second = session.validAccessToken()
        #expect(try await [first, second] == ["ya29.fixture-refreshed-token", "ya29.fixture-refreshed-token"])
        #expect(http.requests.count == 1)
        #expect(http.requests[0].formFields["refresh_token"] == "1//stored")
    }

    @Test func signedOutSessionThrows() async throws {
        let session = GmailSession(accountID: .generate(), http: FixtureHTTPClient([:]), keychain: keychain)
        await #expect(throws: GmailSession.Failure.signedOut) { try await session.validAccessToken() }
    }

    @Test func signatureIsTheDefaultAddresssAsPlainText() async throws {
        let http = FixtureHTTPClient([
            "/token": [.init(fixture: "token-exchange")],
            "/gmail/v1/users/me/settings/sendAs": [.init(fixture: "send-as")],
        ])
        let signature = try await GmailClient(session: try await signedIn(http), http: http).signature()
        #expect(signature == "Dana Levi\nGoodmail & Co.\n\nexample.com")
    }
}
