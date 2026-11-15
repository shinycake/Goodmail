import Foundation
import MailCore
import Testing

@testable import OutlookProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// The fixture mailbox's user folders are קבלות (AAReceipts) at the root and Inbox/Projects (AAProjects).
struct OutlookLabelTests {
    /// The fixture mailbox, where a name filter finds only the Inbox and every create answers with AANew.
    private static func mailbox(_ request: URLRequest) -> String? {
        if request.url?.host() != "graph.microsoft.com" { return FixtureGraph.mailbox(request) }
        if request.httpMethod == "POST" { return "folder-created" }
        if request.httpMethod != "GET" { return "empty-page" }
        if let filter = request.query("$filter"), filter.hasPrefix("displayName eq") {
            return filter == "displayName eq 'Inbox'" ? "folders-inbox-only" : "empty-page"
        }
        return FixtureGraph.mailbox(request)
    }

    /// The changes `body` sends, in order.
    private func changes(
        routing route: @escaping @Sendable (URLRequest) -> String? = Self.mailbox,
        _ body: (OutlookClient) async throws -> Void
    ) async throws -> [String] {
        let graph = FixtureGraph(route)
        try await body(try await OutlookClient.signedIn(to: graph))
        return graph.requests.filter { $0.httpMethod != "GET" && $0.url?.host() == "graph.microsoft.com" }
            .map(\.summary)
    }

    @Test func aNewFolderIsMadeAlongItsPathCreatingTheFoldersMissingOnIt() async throws {
        var label: MailLabel?
        let sent = try await changes { label = try await $0.createLabel(named: "Inbox/Bills/2026") }

        #expect(
            sent == [
                #"POST me/mailFolders/AAInbox/childFolders {"displayName":"Bills"}"#,
                #"POST me/mailFolders/AANew/childFolders {"displayName":"2026"}"#,
            ])
        #expect(label == MailLabel(id: "AANew", name: "Inbox/Bills/2026", kind: .user))
    }

    @Test func aFolderAtTheTopIsMadeThere() async throws {
        let sent = try await changes { _ = try await $0.createLabel(named: "חשבוניות") }
        #expect(sent == [#"POST me/mailFolders {"displayName":"חשבוניות"}"#])
    }

    @Test(arguments: ["", "Inbox//Bills", " / "])
    func aPathWithAnEmptyNameIsRejectedUnsent(_ name: String) async throws {
        let graph = FixtureGraph(Self.mailbox)
        let outlook = try await OutlookClient.signedIn(to: graph)
        await #expect(throws: ProviderError.rejected) { try await outlook.createLabel(named: name) }
        #expect(graph.requests.isEmpty)
    }

    @Test func aTakenNameIsRejected() async throws {
        await #expect(throws: ProviderError.rejected) {
            let refusing: @Sendable (URLRequest) -> String? = { $0.isGraphPOST ? "status-409" : Self.mailbox($0) }
            _ = try await changes(routing: refusing) { _ = try await $0.createLabel(named: "Projects") }
        }
    }

    @Test func aNewNameInTheSameFolderOnlyRenames() async throws {
        let sent = try await changes { try await $0.renameLabel("AAProjects", to: "Inbox/Plans") }
        #expect(sent == [#"PATCH me/mailFolders/AAProjects {"displayName":"Plans"}"#])
    }

    @Test func aPathInAnotherFolderMovesTheFolderThere() async throws {
        let up = try await changes { try await $0.renameLabel("AAProjects", to: "Projects") }
        #expect(up == [#"POST me/mailFolders/AAProjects/move {"destinationId":"msgfolderroot"}"#])

        let renamedAndMoved = try await changes { try await $0.renameLabel("AAReceipts", to: "Inbox/Receipts") }
        #expect(
            renamedAndMoved == [
                #"PATCH me/mailFolders/AAReceipts {"displayName":"Receipts"}"#,
                #"POST me/mailFolders/AAReceipts/move {"destinationId":"AAInbox"}"#,
            ])
    }

    @Test func renamingAFolderThatIsGoneIsNotFound() async throws {
        await #expect(throws: ProviderError.notFound) {
            _ = try await changes { try await $0.renameLabel("AAGone", to: "Plans") }
        }
    }

    @Test func deletingAFolderThatIsAlreadyGoneSucceeds() async throws {
        let gone: @Sendable (URLRequest) -> String? = { $0.httpMethod == "DELETE" ? nil : Self.mailbox($0) }
        let sent = try await changes(routing: gone) { try await $0.deleteLabel("AAProjects") }
        #expect(sent == ["DELETE me/mailFolders/AAProjects "])
    }
}

extension URLRequest {
    fileprivate var isGraphPOST: Bool { httpMethod == "POST" && url?.host() == "graph.microsoft.com" }
}
