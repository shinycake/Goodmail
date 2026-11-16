import AppIntents
import Foundation
import MailCore
import Testing

@testable import MailIntents

/// A message or a conversation handed to an action that takes text, such as Use Model, reads as an email printout:
/// who wrote it, to whom and when, then what it says.
struct MailTextTests {
    private let account = Account(
        id: AccountID(rawValue: "A1"), email: "me@example.com", color: .teal, service: .gmail)

    private func thread(_ id: String) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Lunch", snippet: "See you at one",
            sender: Contact(name: "Yael", address: "yael@example.com"), date: .now, isUnread: true,
            messageCount: 2, labelIDs: [SystemLabel.inbox])
    }

    private func message(_ id: String, body: String, cc: [Contact] = [], minutesAgo: Double = 0) -> Message {
        Message(
            id: Message.ID(accountID: account.id, messageID: id), threadID: "t",
            from: Contact(name: "Yael", address: "yael@example.com"),
            to: [Contact(name: nil, address: "me@example.com")], cc: cc, subject: "Lunch",
            date: .now - minutesAgo * 60,
            labelIDs: [SystemLabel.inbox], body: MessageBody(plain: body),
            attachments: [Attachment(id: "1", filename: "menu.pdf", mimeType: "application/pdf", size: 2048)])
    }

    private func catalog(_ messages: [Message]) -> Catalog {
        var host = FakeHost(accountList: [account])
        let thread = thread("t")
        host.stored = [thread]
        host.cached[thread.id] = messages
        return Catalog(host: host)
    }

    @Test func aMessageReadsAsItsHeadersThenItsBody() throws {
        let catalog = catalog([
            message("m", body: "See you at one", cc: [Contact(name: "Dan", address: "dan@example.com")])
        ])
        let entity = try #require(try catalog.messages(["A1/t/m"]).first)
        let lines = entity.plainText.components(separatedBy: "\n")
        #expect(lines.first == "From: Yael <yael@example.com>")
        #expect(lines.contains("To: me@example.com"))
        #expect(lines.contains("Cc: Dan <dan@example.com>"))
        #expect(lines.contains("Subject: Lunch"))
        #expect(lines.contains("Attachments: menu.pdf"))
        #expect(lines.contains { $0.hasPrefix("Date: ") })
        #expect(lines.last == "See you at one")
    }

    @Test func aMessageWithoutCcLeavesTheLineOut() throws {
        let entity = try #require(try catalog([message("m", body: "Hi")]).messages(["A1/t/m"]).first)
        #expect(!entity.plainText.contains("Cc:"))
    }

    @Test func aConversationReadsAsEachOfItsMessagesOldestFirst() throws {
        // The store keeps a thread's messages newest first.
        let catalog = catalog([message("m2", body: "Second"), message("m1", body: "First", minutesAgo: 10)])
        let entity = try #require(try catalog.threads(["A1/t"]).first)
        let text = entity.plainText
        let first = try #require(text.range(of: "First"))
        let second = try #require(text.range(of: "Second"))
        #expect(first.lowerBound < second.lowerBound)
        #expect(text.components(separatedBy: "From: ").count == 3)
    }

    @Test func aConversationWithNothingCachedReadsAsItsPreview() {
        let text = ThreadEntity(thread("t")).plainText
        #expect(text.hasPrefix("From: Yael <yael@example.com>\n"))
        #expect(text.hasSuffix("\n\nSee you at one"))
    }
}

/// The reader tells Siri which conversation is on screen.
struct ReadingActivityTests {
    @Test func theActivityNamesTheConversation() throws {
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "A1"), threadID: "t"), subject: "Lunch",
            snippet: "", sender: Contact(name: nil, address: "yael@example.com"), date: .now, isUnread: false,
            messageCount: 1, labelIDs: [])
        let activity = NSUserActivity.reading(thread)
        #expect(activity.title == "Lunch")
        let identifier = try #require(activity.appEntityIdentifier)
        #expect(identifier == EntityIdentifier(for: ThreadEntity.self, identifier: "A1/t"))
    }
}
