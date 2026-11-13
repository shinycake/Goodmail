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
        let session = try await OAuthSession.signIn(
            client: .gmail, code: "4/abc", pkce: .generate(), http: http, keychain: keychain)
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

    @Test func smallMessagesGoAsJSONInTheirThread() async throws {
        let (gmail, http) = try await client(["/gmail/v1/users/me/messages/send": [.init(fixture: "message-sent")]])
        try await gmail.send(Data("Subject: Hi\r\n\r\nHello".utf8), inThread: "t1")
        let request = try #require(http.requests.last)
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body["threadId"] == "t1")
        #expect(body["raw"] == Data("Subject: Hi\r\n\r\nHello".utf8).base64URLEncodedString())
    }

    @Test func aNewDraftIsCreatedInItsThread() async throws {
        let (gmail, http) = try await client(["/gmail/v1/users/me/drafts": [.init(fixture: "draft")]])
        try await gmail.saveDraft(Data("Subject: Hi".utf8), inThread: "18f0a1", replacing: nil)
        let request = try #require(http.requests.last)
        #expect(request.httpMethod == "POST")
        let body = try JSONDecoder().decode(
            [String: [String: String]].self, from: try #require(request.httpBody))
        #expect(body["message"] == ["threadId": "18f0a1", "raw": Data("Subject: Hi".utf8).base64URLEncodedString()])
    }

    @Test func savingAgainReplacesTheDraftHoldingTheMessage() async throws {
        let (gmail, http) = try await client([
            "/gmail/v1/users/me/drafts": [.init(fixture: "drafts-list")],
            "/gmail/v1/users/me/drafts/r-222": [.init(fixture: "draft")],
        ])
        let saved = Message.ID(accountID: AccountID(rawValue: "a"), messageID: "18f0b2")
        try await gmail.saveDraft(Data("Subject: Hi".utf8), inThread: "18f0a1", replacing: saved)
        #expect(http.requests.last?.httpMethod == "PUT")
        #expect(http.requests.last?.url?.path() == "/gmail/v1/users/me/drafts/r-222")
    }

    @Test func aDraftThatIsGoneIsSavedAsNew() async throws {
        let (gmail, http) = try await client([
            "/gmail/v1/users/me/drafts": [.init(fixture: "drafts-list"), .init(fixture: "draft")]
        ])
        let gone = Message.ID(accountID: AccountID(rawValue: "a"), messageID: "18f0zz")
        try await gmail.saveDraft(Data("Subject: Hi".utf8), inThread: nil, replacing: gone)
        #expect(http.requests.last?.httpMethod == "POST")
    }

    @Test func deletingFindsTheDraftAndToleratesAnEmptyReply() async throws {
        let (gmail, http) = try await client([
            "/gmail/v1/users/me/drafts": [.init(fixture: "drafts-list")],
            "/gmail/v1/users/me/drafts/r-111": [.init(fixture: "empty", status: 204)],
        ])
        try await gmail.deleteDraft(Message.ID(accountID: AccountID(rawValue: "a"), messageID: "18f0b1"))
        #expect(http.requests.last?.httpMethod == "DELETE")
        #expect(http.requests.last?.url?.path() == "/gmail/v1/users/me/drafts/r-111")
        let before = http.requests.count
        try await gmail.deleteDraft(Message.ID(accountID: AccountID(rawValue: "a"), messageID: "18f0zz"))
        #expect(http.requests.count == before + 1, "only the lookup: nothing to delete")
    }

    @Test func contactsCoverEveryPageOfBothListsOneEntryPerAddress() async throws {
        let (gmail, http) = try await client([
            "/v1/people/me/connections": [
                .init(fixture: "people-connections"), .init(fixture: "people-connections-2"),
            ],
            "/v1/otherContacts": [.init(fixture: "other-contacts")],
        ])
        let contacts = try await gmail.contacts()
        #expect(
            contacts == [
                Contact(name: "Dana Levi", address: "dana@example.com"),
                Contact(name: "Dana Levi", address: "dana@work.example"),
                Contact(name: "יעל כהן", address: "yael@example.co.il"),
                Contact(name: nil, address: "billing@shop.example"),
            ])
        let pages = http.requests.filter { $0.url?.host() == "people.googleapis.com" }
        #expect(pages.count == 3)
        #expect(pages[1].url?.query()?.contains("pageToken=page-2") == true)
        #expect(pages[2].url?.query()?.contains("readMask=names,emailAddresses") == true)
    }

    @Test func largeMessagesAreUploadedWithTheirThread() async throws {
        let (gmail, http) = try await client([
            "/upload/gmail/v1/users/me/messages/send": [.init(fixture: "message-sent")]
        ])
        let raw = Data(repeating: UInt8(ascii: "a"), count: GmailClient.jsonSendLimit + 1)
        try await gmail.send(raw, inThread: "t1")
        let request = try #require(http.requests.last)
        #expect(request.url?.query() == "uploadType=multipart")
        let type = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(type.hasPrefix("multipart/related; boundary="))
        let body = try #require(request.httpBody)
        let text = String(decoding: body.prefix(400), as: UTF8.self)
        #expect(text.contains("Content-Type: application/json; charset=UTF-8\r\n\r\n{\"threadId\":\"t1\"}"))
        #expect(text.contains("Content-Type: message/rfc822\r\n\r\naaaa"))
        #expect(body.count > raw.count)
    }

    @Test func searchTextLeadsTheQuery() {
        let query = ThreadQuery(before: Date(timeIntervalSince1970: 1_800_000_000), text: "from:dana invoice")
        #expect(query.gmailSearch == "from:dana invoice before:1800000000")
        #expect(ThreadQuery(text: "  ").gmailSearch == nil)
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
