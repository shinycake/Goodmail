import Foundation
import MailCore
import Testing

@testable import MailIntents

struct CatalogTests {
    private let account = Account(
        id: AccountID(rawValue: "A1"), email: "tester@example.com", color: .teal, service: .gmail)
    /// A host with the one account, for each test to fill.
    private var host: FakeHost { FakeHost(accountList: [account]) }

    private func thread(_ id: String, labels: Set<String> = [SystemLabel.inbox]) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Subject \(id)", snippet: "Snippet",
            sender: Contact(name: "Yael", address: "yael@example.com"), date: .now, isUnread: true, messageCount: 1,
            labelIDs: labels)
    }

    private func message(_ id: String, in thread: String, labels: Set<String>) -> Message {
        Message(
            id: Message.ID(accountID: account.id, messageID: id), threadID: thread,
            from: Contact(name: "Yael", address: "yael@example.com"),
            to: [Contact(name: nil, address: "tester@example.com")], subject: "Hello", date: .now, labelIDs: labels,
            body: MessageBody(html: "<p>Hi &amp; bye</p>"))
    }

    @Test func threadIdentifiersRoundTrip() throws {
        var host = self.host
        host.stored = [thread("t1")]
        let catalog = Catalog(host: host)
        let entity = try #require(try catalog.recentThreads().first)
        #expect(entity.id == "A1/t1")
        #expect(try catalog.threads([entity.id]).map(\.title) == ["Subject t1"])
        #expect(try catalog.threads(["nonsense", "A1/gone"]).isEmpty)
    }

    @Test func aThreadCarriesItsCachedMessagesInTheMailboxTheyAreIn() throws {
        var host = self.host
        let summary = thread("t1")
        host.stored = [summary]
        host.cached[summary.id] = [
            message("m1", in: "t1", labels: [SystemLabel.inbox, SystemLabel.unread, "CATEGORY_SOCIAL"]),
            message("m2", in: "t1", labels: [SystemLabel.sent, SystemLabel.starred]),
        ]
        let entity = try #require(try Catalog(host: host).threads(["A1/t1"]).first)
        let first = try #require(entity.messages.first)
        #expect(entity.messages.map(\.id) == ["A1/t1/m1", "A1/t1/m2"])
        #expect(first.mailbox.id == "A1/INBOX")
        #expect(first.account.emailAddress == "tester@example.com")
        #expect(first.isRead == false)
        #expect(first.category == .social)
        #expect(first.body == "Hi & bye")
        #expect(entity.messages[1].mailbox.id == "A1/SENT")
        #expect(entity.messages[1].isFlagged)
        #expect(entity.messages[1].category == nil)
    }

    @Test func aThreadNotYetFetchedHasNoMessages() throws {
        var host = self.host
        host.stored = [thread("t1")]
        #expect(try Catalog(host: host).threads(["A1/t1"]).first?.messages.isEmpty == true)
    }

    @Test func messagesAreFoundByIdentifier() throws {
        var host = self.host
        let summary = thread("t1")
        host.stored = [summary]
        host.cached[summary.id] = [
            message("m1", in: "t1", labels: [SystemLabel.inbox]), message("m2", in: "t1", labels: [SystemLabel.trash]),
        ]
        let found = try Catalog(host: host).messages(["A1/t1/m2", "A1/t1/missing"])
        #expect(found.map(\.id) == ["A1/t1/m2"])
        #expect(found.first?.mailbox.id == "A1/TRASH")
    }

    @Test func notJunkTakesOnlyJunkBackToTheInbox() async throws {
        var host = self.host
        let junk = thread("t1")
        let archived = thread("t2")
        host.stored = [junk, archived]
        host.cached[junk.id] = [message("m1", in: "t1", labels: [SystemLabel.spam])]
        host.cached[archived.id] = [message("m2", in: "t2", labels: [])]
        let catalog = Catalog(host: host)
        try await catalog.markNotJunk(try catalog.messages(["A1/t1/m1", "A1/t2/m2"]))
        #expect(host.performed.on("t1") == [.moveToInbox])
        #expect(host.performed.on("t2").isEmpty)
    }

    @Test func everyAccountOffersItsMailboxesAndLabels() throws {
        var host = self.host
        let label = Mailbox(labelID: "Label_7", accountID: account.id)
        host.labels[account.id] = [NamedMailbox(mailbox: label, name: "Receipts")]
        let mailboxes = try Catalog(host: host).mailboxes()
        #expect(mailboxes.map(\.id).contains("A1/"))
        #expect(mailboxes.last?.id == "A1/Label_7")
        #expect(mailboxes.last?.name == "Receipts")
        #expect(mailboxes.last?.mailbox == label)
        #expect(mailboxes.first?.mailbox == Mailbox(labelID: SystemLabel.inbox, accountID: account.id))
    }

    @Test func openingAThreadReadsItFromTheMailboxItIsIn() throws {
        var host = self.host
        host.stored = [thread("t1", labels: [SystemLabel.spam]), thread("t2", labels: ["Label_7"])]
        let catalog = Catalog(host: host)
        let t1 = ThreadSummary.ID(accountID: account.id, threadID: "t1")
        let t2 = ThreadSummary.ID(accountID: account.id, threadID: "t2")
        #expect(try catalog.route(toThread: "A1/t1") == .thread(t1, in: .spam))
        #expect(try catalog.route(toThread: "A1/t2") == .thread(t2, in: .allMail))
        #expect(try catalog.route(toThread: "A1/gone") == nil)
    }
}
