import Foundation
import MailCore
import Testing

@testable import OutlookProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Conversation c1 holds m3, unread in the Inbox, and m1, flagged in Sent Items. Conversation c2 holds m4, read in
/// the user's Inbox/Projects folder.
struct OutlookActionTests {
    /// The fixture mailbox, answering every change to a message with success.
    private static func mailbox(_ request: URLRequest) -> String? {
        let changesMessage = request.httpMethod != "GET" && request.graphPath.hasPrefix("me/messages/")
        return changesMessage ? "empty-page" : FixtureGraph.mailbox(request)
    }

    private func perform(_ action: ThreadAction, on thread: String = "c1") async throws -> [String] {
        let graph = FixtureGraph(Self.mailbox)
        let outlook = try await OutlookClient.signedIn(to: graph)
        try await outlook.perform(action, onThread: thread)
        return graph.requests.filter { $0.httpMethod != "GET" && $0.url?.host() == "graph.microsoft.com" }
            .map(\.summary).sorted()
    }

    @Test func archiveFilesTheInboxMessageAndLeavesSentMailWhereItIs() async throws {
        #expect(try await perform(.archive) == [#"POST me/messages/m3/move {"destinationId":"AAArchive"}"#])
    }

    @Test func readAndStarAreFlagsSetOnlyWhereTheyDiffer() async throws {
        #expect(try await perform(.markRead(true)) == [#"PATCH me/messages/m3 {"isRead":true}"#])
        #expect(
            try await perform(.star(false)) == [#"PATCH me/messages/m1 {"flag":{"flagStatus":"notFlagged"}}"#])
        #expect(try await perform(.markRead(false)) == [#"PATCH me/messages/m1 {"isRead":false}"#])
    }

    @Test func trashTakesTheWholeConversationSentMailIncluded() async throws {
        #expect(
            try await perform(.trash) == [
                #"POST me/messages/m1/move {"destinationId":"AATrash"}"#,
                #"POST me/messages/m3/move {"destinationId":"AATrash"}"#,
            ])
    }

    @Test func aMessageDeletedMeanwhileIsSkipped() async throws {
        let graph = FixtureGraph { request in
            request.graphPath == "me/messages/m1/move" ? nil : Self.mailbox(request)
        }
        let outlook = try await OutlookClient.signedIn(to: graph)
        try await outlook.perform(.trash, onThread: "c1")
        #expect(graph.requests.contains { $0.graphPath == "me/messages/m3/move" })
    }

    @Test func aMoveToAUserFolderFilesOnlyTheMessagesThatLeaveTheMailbox() async throws {
        #expect(
            try await perform(.move(to: .label("AAReceipts"), from: .inbox)) == [
                #"POST me/messages/m3/move {"destinationId":"AAReceipts"}"#
            ])
    }

    @Test func aGoneConversationIsNotFoundAndAnUnknownFolderIsRefused() async throws {
        await #expect(throws: ProviderError.notFound) { try await perform(.archive, on: "gone") }
        await #expect(throws: ProviderError.rejected) {
            try await perform(.modifyLabels(add: ["AANoSuchFolder"], remove: []), on: "c2")
        }
    }

    @Test func replayingAnActionThatAlreadyHappenedChangesNothing() throws {
        let folders = FolderDirectory(
            wellKnown: [.inbox: "AAInbox", .archive: "AAArchive", .deleteditems: "AATrash"], user: [])
        let archived = GraphMessage(id: "m", parentFolderId: "AAArchive", isRead: true, flagged: false)
        #expect(try GraphChange.changes(for: .archive, to: archived, in: folders) == [])
        #expect(try GraphChange.changes(for: .markRead(true), to: archived, in: folders) == [])
        #expect(try GraphChange.changes(for: .untrash, to: archived, in: folders) == [])

        let trashed = GraphMessage(id: "m", parentFolderId: "AATrash", isRead: true, flagged: false)
        // Untrash leaves the message out of the Inbox, as it does a Gmail thread; undo adds the Inbox back.
        #expect(try GraphChange.changes(for: .untrash, to: trashed, in: folders) == [.move(toFolder: "AAArchive")])
    }

    @Test func deleteForeverDeletesOnlyTheMessagesInDeletedItems() throws {
        let folders = FolderDirectory(wellKnown: [.inbox: "AAInbox", .deleteditems: "AATrash"], user: [])
        let trashed = GraphMessage(id: "m", parentFolderId: "AATrash", isRead: true, flagged: false)
        let inInbox = GraphMessage(id: "m", parentFolderId: "AAInbox", isRead: false, flagged: false)
        #expect(try GraphChange.changes(for: .deleteForever, to: trashed, in: folders) == [.permanentDelete])
        #expect(try GraphChange.changes(for: .deleteForever, to: inInbox, in: folders) == [])
    }

    @Test func deleteForeverIsAPermanentDeleteOfTheTrashedMessagesOnly() async throws {
        #expect(try await perform(.deleteForever, on: "c3") == ["POST me/messages/m7/permanentDelete "])
        #expect(try await perform(.deleteForever, on: "c1") == [], "nothing of c1 is in Trash")
    }

    @Test func aMailboxWithoutArchiveCanStillTrashButNotArchive() throws {
        let folders = FolderDirectory(wellKnown: [.inbox: "AAInbox", .deleteditems: "AATrash"], user: [])
        let inInbox = GraphMessage(id: "m", parentFolderId: "AAInbox", isRead: true, flagged: false)
        #expect(try GraphChange.changes(for: .trash, to: inInbox, in: folders) == [.move(toFolder: "AATrash")])
        #expect(throws: GraphChange.Failure.noFolder) {
            try GraphChange.changes(for: .archive, to: inInbox, in: folders)
        }
    }
}

extension GraphMessage {
    init(id: String, parentFolderId: String, isRead: Bool, flagged: Bool) {
        self.init(
            id: id, conversationId: nil, subject: nil, bodyPreview: nil, from: nil, receivedDateTime: nil,
            isRead: isRead, flag: Flag(flagStatus: flagged ? "flagged" : "notFlagged"),
            parentFolderId: parentFolderId)
    }
}

extension URLRequest {
    /// The method, Graph path and JSON body, as in `PATCH me/messages/m1 {"isRead":true}`.
    fileprivate var summary: String {
        let body = httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return [httpMethod ?? "", graphPath, body].joined(separator: " ")
    }
}
