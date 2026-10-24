import Foundation
import MailCore
import Testing

@testable import GmailProvider

/// The provider half of sync: cursors, history, windowed queries and the failure paths, on fixtures.
struct GmailSyncTests {
    private let keychain = InMemorySecretStore()

    private func client(_ replies: [String: [FixtureHTTPClient.Reply]]) async throws -> (GmailClient, FixtureHTTPClient)
    {
        var replies = replies
        replies["/token"] = [.init(fixture: "token-exchange")]
        let http = FixtureHTTPClient(replies)
        let session = try await GmailSession.signIn(code: "4/abc", pkce: .generate(), http: http, keychain: keychain)
        return (GmailClient(session: session.session, http: http, retryDelays: [.zero, .zero]), http)
    }

    @Test func labelsMapKindColorAndVisibility() async throws {
        let (gmail, _) = try await client(["/gmail/v1/users/me/labels": [.init(fixture: "labels")]])
        let labels = try await gmail.labels()
        #expect(labels.map(\.id) == ["INBOX", "CATEGORY_SOCIAL", "Label_7", "Label_8"])
        #expect(labels[0].kind == .system)
        #expect(labels[2] == MailLabel(id: "Label_7", name: "קבלות", kind: .user, color: "#16a766"))
        #expect(labels[3].isHidden)
    }

    @Test func currentCursorIsTheProfileHistoryID() async throws {
        let (gmail, _) = try await client(["/gmail/v1/users/me/profile": [.init(fixture: "profile")]])
        #expect(try await gmail.currentCursor() == "9001")
    }

    @Test func changesCollectThreadsAcrossHistoryPages() async throws {
        let (gmail, http) = try await client([
            "/gmail/v1/users/me/history": [.init(fixture: "history-page1"), .init(fixture: "history-page2")]
        ])
        let changes = try await gmail.changes(since: "9001")
        #expect(changes == ChangeSet(threadIDs: ["18f0a1", "18f0a2", "18f0a4"], cursor: "9012"))

        let pages = http.requests.filter { $0.url!.path().hasSuffix("/history") }.map { $0.url!.query()! }
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { $0.contains("startHistoryId=9001") })
        #expect(pages[1].contains("pageToken=page-2"))
    }

    @Test func noHistoryKeepsTheCursorMoving() async throws {
        let (gmail, _) = try await client(["/gmail/v1/users/me/history": [.init(fixture: "history-empty")]])
        #expect(try await gmail.changes(since: "9001") == ChangeSet(threadIDs: [], cursor: "9001"))
    }

    @Test func historyNotFoundMeansTheCursorExpired() async throws {
        let (gmail, _) = try await client([
            "/gmail/v1/users/me/history": [.init(fixture: "not-found", status: 404)]
        ])
        await #expect(throws: ProviderError.cursorExpired) { try await gmail.changes(since: "1") }
    }

    @Test func deletedThreadsAreReportedMissing() async throws {
        let (gmail, _) = try await client([
            "/gmail/v1/users/me/threads/18f0a4": [.init(fixture: "thread-18f0a4")],
            "/gmail/v1/users/me/threads/18f0a2": [.init(fixture: "not-found", status: 404)],
        ])
        let fetch = try await gmail.threads(withIDs: ["18f0a2", "18f0a4"])
        #expect(fetch.found.map(\.id.threadID) == ["18f0a4"])
        #expect(fetch.found.first?.subject == "Arrived")
        #expect(fetch.missing == ["18f0a2"])
    }

    @Test func windowedQueriesSendLabelDatesAndPageToken() async throws {
        let (gmail, http) = try await client([
            "/gmail/v1/users/me/threads": [.init(fixture: "threads-inbox")],
            "/gmail/v1/users/me/threads/18f0a1": [.init(fixture: "thread-18f0a1")],
            "/gmail/v1/users/me/threads/18f0a2": [.init(fixture: "thread-18f0a2")],
            "/gmail/v1/users/me/threads/18f0a3": [.init(fixture: "thread-18f0a3")],
        ])
        let query = ThreadQuery(
            label: "SENT", since: Date(timeIntervalSince1970: 1_700_000_000),
            before: Date(timeIntervalSince1970: 1_800_000_000))
        _ = try await gmail.threads(matching: query, pageToken: "next-1")

        let list = try #require(http.requests.first { $0.url!.path().hasSuffix("/threads") })
        let items = try #require(URLComponents(url: list.url!, resolvingAgainstBaseURL: false)?.queryItems)
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        #expect(fields["labelIds"] == "SENT")
        #expect(fields["q"] == "after:1700000000 before:1800000000")
        #expect(fields["pageToken"] == "next-1")
        #expect(fields["maxResults"] == "50")
    }

    @Test func rateLimitedRequestsAreRetried() async throws {
        let (gmail, http) = try await client([
            "/gmail/v1/users/me/profile": [
                .init(fixture: "rate-limited", status: 429), .init(fixture: "rate-limited", status: 403),
                .init(fixture: "profile"),
            ]
        ])
        #expect(try await gmail.currentCursor() == "9001")
        #expect(http.requests.filter { $0.url!.path().hasSuffix("/profile") }.count == 3)
    }

    @Test func persistentFailureGivesUpAfterTheRetries() async throws {
        let (gmail, http) = try await client([
            "/gmail/v1/users/me/profile": [.init(fixture: "rate-limited", status: 503)]
        ])
        await #expect(throws: GmailError.self) { try await gmail.currentCursor() }
        #expect(http.requests.filter { $0.url!.path().hasSuffix("/profile") }.count == 3, "one try and two retries")
    }

    @Test func clientErrorsAreNotRetried() async throws {
        let (gmail, http) = try await client([
            "/gmail/v1/users/me/profile": [.init(fixture: "not-found", status: 400)]
        ])
        await #expect(throws: GmailError.self) { try await gmail.currentCursor() }
        #expect(http.requests.filter { $0.url!.path().hasSuffix("/profile") }.count == 1)
    }
}
