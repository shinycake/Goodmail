import Foundation
import MailCore
import Testing

@testable import GmailProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLRequest on Linux
#endif

struct GmailLabelTests {
    private let keychain = InMemorySecretStore()

    private func client(_ http: FixtureHTTPClient) async throws -> GmailClient {
        let session = try await OAuthSession.signIn(
            client: .gmail, code: "4/abc", pkce: .generate(), http: http, keychain: keychain
        ).session
        return GmailClient(session: session, http: http, retryDelays: [])
    }

    private static func replies(
        _ more: [String: [FixtureHTTPClient.Reply]]
    ) -> [String: [FixtureHTTPClient.Reply]] {
        more.merging(["/token": [.init(fixture: "token-exchange")]]) { mine, _ in mine }
    }

    private func names(in request: URLRequest) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
    }

    @Test func aNewLabelIsPostedByItsPathAndReturned() async throws {
        let http = FixtureHTTPClient(
            Self.replies(["/gmail/v1/users/me/labels": [.init(fixture: "label-created")]]))

        let label = try await client(http).createLabel(named: "Projects/Goodmail")

        #expect(label == MailLabel(id: "Label_9", name: "Projects/Goodmail", kind: .user))
        let post = try #require(http.requests.last)
        #expect(post.httpMethod == "POST")
        #expect(try names(in: post) == ["name": "Projects/Goodmail"])
    }

    @Test func aTakenNameIsRejected() async throws {
        let http = FixtureHTTPClient(
            Self.replies(["/gmail/v1/users/me/labels": [.init(fixture: "label-conflict", status: 409)]]))
        await #expect(throws: ProviderError.rejected) { try await client(http).createLabel(named: "Projects") }
    }

    @Test func renamingALabelRenamesTheLabelsNestedInItAndNoOthers() async throws {
        let http = FixtureHTTPClient(
            Self.replies([
                "/gmail/v1/users/me/labels": [.init(fixture: "labels-nested")],
                "/gmail/v1/users/me/labels/Label_1": [.init(fixture: "label-created")],
                "/gmail/v1/users/me/labels/Label_2": [.init(fixture: "label-created")],
                "/gmail/v1/users/me/labels/Label_3": [.init(fixture: "label-created")],
            ]))

        try await client(http).renameLabel("Label_1", to: "פרויקטים")

        let patches = http.requests.filter { $0.httpMethod == "PATCH" }
        #expect(
            patches.map { $0.url?.lastPathComponent } == ["Label_1", "Label_2", "Label_3"],
            "the label first, then those under it; not one whose name only starts the same")
        #expect(
            try patches.map { try names(in: $0)["name"] } == [
                "פרויקטים", "פרויקטים/Goodmail", "פרויקטים/Goodmail/Design",
            ])
    }

    @Test func renamingALabelThatIsGoneIsNotFound() async throws {
        let http = FixtureHTTPClient(Self.replies(["/gmail/v1/users/me/labels": [.init(fixture: "labels-nested")]]))
        await #expect(throws: ProviderError.notFound) { try await client(http).renameLabel("Label_99", to: "X") }
    }

    @Test func deletingALabelDeletesTheLabelsNestedInItFirstAndNoOthers() async throws {
        let http = FixtureHTTPClient(
            Self.replies([
                "/gmail/v1/users/me/labels": [.init(fixture: "labels-nested")],
                "/gmail/v1/users/me/labels/Label_1": [.init(fixture: "empty", status: 204)],
                // One that another client deleted meanwhile doesn't stop the rest.
                "/gmail/v1/users/me/labels/Label_2": [.init(fixture: "not-found", status: 404)],
                "/gmail/v1/users/me/labels/Label_3": [.init(fixture: "empty", status: 204)],
            ]))

        try await client(http).deleteLabel("Label_1")

        let deletes = http.requests.filter { $0.httpMethod == "DELETE" }
        #expect(deletes.map { $0.url?.lastPathComponent } == ["Label_2", "Label_3", "Label_1"])
    }

    @Test func deletingALabelThatIsAlreadyGoneSendsNothing() async throws {
        let http = FixtureHTTPClient(Self.replies(["/gmail/v1/users/me/labels": [.init(fixture: "labels-nested")]]))

        try await client(http).deleteLabel("Label_99")

        #expect(!http.requests.contains { $0.httpMethod == "DELETE" })
    }
}
