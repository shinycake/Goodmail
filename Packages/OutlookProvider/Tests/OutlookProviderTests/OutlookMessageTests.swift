import Foundation
import MailCore
import Testing

@testable import OutlookProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// Conversation c1: m1 from me in Sent Items, flagged, then Dana's reply m3, unread in the Inbox, with a PDF.
struct OutlookMessageTests {
    private static func mailbox(_ request: URLRequest) -> String? {
        switch request.graphPath {
        case "me/messages/m1/$value": "m1.eml"
        case "me/messages/m3/$value": "m3.eml"
        default: FixtureGraph.mailbox(request)
        }
    }

    @Test func aConversationReadsAsItsParsedMessagesOldestFirst() async throws {
        let outlook = try await OutlookClient.signedIn(to: FixtureGraph(Self.mailbox))
        let messages = try await outlook.messages(inThread: "c1")

        #expect(messages.map(\.id.messageID) == ["m1", "m3"])
        let (mine, reply) = (messages[0], messages[1])
        #expect(mine.labelIDs == ["SENT", "STARRED"])
        #expect(mine.bcc.isEmpty)
        #expect(mine.body.plain == "Are you free?")

        #expect(reply.threadID == "c1")
        #expect(reply.from == Contact(name: "Dana Levi", address: "dana@example.com"))
        #expect(reply.cc == [Contact(name: "יוסי", address: "yossi@example.co.il")])
        #expect(reply.subject == "RE: Lunch plans")
        #expect(reply.isUnread)
        #expect(reply.snippet == "Thursday works")
        #expect(reply.internetMessageID == "m3@example.com")
        #expect(reply.references == ["m1@outlook.com"])
        #expect(reply.body.html == "<p>Thursday works</p>")
        #expect(reply.attachments.map(\.filename) == ["menu.pdf"])
    }

    @Test func anAttachmentComesFromTheMessagesMIME() async throws {
        let outlook = try await OutlookClient.signedIn(to: FixtureGraph(Self.mailbox))
        let reply = try await outlook.messages(inThread: "c1")[1]
        let pdf = try #require(reply.attachments.first)
        #expect(try await outlook.data(for: pdf, in: reply.id) == Data("%PDF-1.4\n".utf8))
    }

    @Test func aGoneConversationOrAttachmentIsNotFound() async throws {
        let outlook = try await OutlookClient.signedIn(to: FixtureGraph(Self.mailbox))
        await #expect(throws: ProviderError.notFound) { try await outlook.messages(inThread: "gone") }
        let gone = Message.ID(accountID: AccountID(rawValue: "o1"), messageID: "AAGone")
        let attachment = Attachment(id: "2", filename: "menu.pdf", mimeType: "application/pdf", size: 9)
        await #expect(throws: ProviderError.notFound) { try await outlook.data(for: attachment, in: gone) }
    }

    @Test func aMessageDeletedSinceTheListingIsLeftOut() async throws {
        let outlook = try await OutlookClient.signedIn(
            to: FixtureGraph { $0.graphPath == "me/messages/m1/$value" ? nil : Self.mailbox($0) })
        #expect(try await outlook.messages(inThread: "c1").map(\.id.messageID) == ["m3"])
    }
}
