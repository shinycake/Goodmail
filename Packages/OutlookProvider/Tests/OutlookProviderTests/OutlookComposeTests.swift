import Foundation
import MailCore
import Testing

@testable import OutlookProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

struct OutlookComposeTests {
    private static let raw = Data("From: me@outlook.com\r\nTo: dana@example.com\r\nSubject: Hi\r\n\r\nשלום\r\n".utf8)

    /// The fixture mailbox, plus what sending, drafts and contacts ask for.
    private static func mailbox(_ request: URLRequest) -> String? {
        switch (request.httpMethod ?? "", request.graphPath) {
        case ("POST", "me/sendMail"), ("POST", "me/messages/AADraftOld/permanentDelete"): "empty-page"
        case ("POST", "me/messages"): "created-draft"
        case ("GET", "me/contacts"): request.query("$skip") == nil ? "contacts-page1" : "contacts-page2"
        case ("GET", "me/people"): "people"
        default: FixtureGraph.mailbox(request)
        }
    }

    private func signedIn(_ route: @escaping @Sendable (URLRequest) -> String? = Self.mailbox) async throws
        -> (OutlookClient, FixtureGraph)
    {
        let graph = FixtureGraph(route)
        return (try await OutlookClient.signedIn(to: graph), graph)
    }

    @Test func sendingPostsTheMessageAsBase64MIME() async throws {
        let (outlook, graph) = try await signedIn()
        try await outlook.send(Self.raw, inThread: "c1")

        let request = try #require(graph.requests.last)
        #expect(request.graphPath == "me/sendMail")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "text/plain")
        #expect(request.httpBody == Self.raw.base64EncodedData())
    }

    @Test func aMessageTooLargeForMIMEIsRefusedWithoutARequest() async throws {
        let (outlook, graph) = try await signedIn()
        let large = Data(repeating: UInt8(ascii: "a"), count: OutlookClient.mimeLimit + 1)
        await #expect(throws: ProviderError.rejected) { try await outlook.send(large, inThread: nil) }
        await #expect(throws: ProviderError.rejected) {
            try await outlook.saveDraft(large, inThread: nil, replacing: nil)
        }
        #expect(!graph.requests.contains { $0.httpMethod == "POST" && $0.url?.host() == "graph.microsoft.com" })
    }

    @Test func aMessageGraphRefusesIsRejected() async throws {
        let (outlook, _) = try await signedIn { request in
            request.graphPath == "me/sendMail" ? "status-400" : Self.mailbox(request)
        }
        await #expect(throws: ProviderError.rejected) { try await outlook.send(Self.raw, inThread: nil) }
    }

    @Test func savingADraftCreatesTheNewOneThenDeletesTheOld() async throws {
        let (outlook, graph) = try await signedIn()
        let old = Message.ID(accountID: AccountID(rawValue: "o1"), messageID: "AADraftOld")
        try await outlook.saveDraft(Self.raw, inThread: "c1", replacing: old)

        let writes = graph.requests.filter { $0.httpMethod == "POST" && $0.url?.host() == "graph.microsoft.com" }
        #expect(writes.map(\.graphPath) == ["me/messages", "me/messages/AADraftOld/permanentDelete"])
        #expect(writes[0].httpBody == Self.raw.base64EncodedData())
        #expect(writes[0].value(forHTTPHeaderField: "Content-Type") == "text/plain")
    }

    @Test func deletingADraftThatIsGoneIsFine() async throws {
        let (outlook, graph) = try await signedIn()
        try await outlook.deleteDraft(Message.ID(accountID: AccountID(rawValue: "o1"), messageID: "AAGone"))
        #expect(graph.requests.last?.graphPath == "me/messages/AAGone/permanentDelete")
    }

    @Test func contactsAreSavedOnesThenPeopleWrittenToOncePerAddress() async throws {
        let (outlook, _) = try await signedIn()
        #expect(
            try await outlook.contacts() == [
                Contact(name: "Dana Levi", address: "dana@example.com"),
                Contact(name: "Dana (work)", address: "dana@work.example.com"),
                Contact(name: "יוסי", address: "yossi@example.co.il"),
                Contact(name: "Shop", address: "shop@example.co.il"),
            ])
    }

    @Test func outlookHasNoSignatureToRead() async throws {
        let (outlook, _) = try await signedIn()
        #expect(try await outlook.signature() == "")
    }
}
