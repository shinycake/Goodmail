import Foundation
import MailCore
import Testing

@testable import MailIntents

/// Send Email, Reply to Message and New Message, as Shortcuts and Siri run them.
struct ComposeActionTests {
    private let account = Account(
        id: AccountID(rawValue: "A1"), email: "me@example.com", color: .teal, service: .gmail)
    private let dana = Contact(name: "Dana", address: "dana@example.com")

    private func message(_ id: String, from sender: Contact, minutesAgo: Double) -> Message {
        Message(
            id: Message.ID(accountID: account.id, messageID: id), threadID: "t1", from: sender,
            to: [Contact(name: nil, address: account.email)], cc: [Contact(name: nil, address: "avi@example.com")],
            subject: "Order", date: .now - minutesAgo * 60, labelIDs: [SystemLabel.inbox],
            body: MessageBody(plain: "Body of \(id)"))
    }

    /// A thread where Dana wrote, the account answered, then Dana wrote again.
    private var host: FakeHost {
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t1"), subject: "Order", snippet: "",
            sender: dana, date: .now, isUnread: true, messageCount: 3, labelIDs: [SystemLabel.inbox])
        return FakeHost(
            accountList: [account], stored: [thread],
            cached: [
                thread.id: [
                    message("m1", from: dana, minutesAgo: 30),
                    message("m2", from: Contact(name: nil, address: account.email), minutesAgo: 20),
                    message("m3", from: dana, minutesAgo: 10),
                ]
            ])
    }

    @Test func anEmailGoesNowOrAtItsTime() async throws {
        let host = host
        let catalog = Catalog(host: host)
        let draft = try catalog.newDraft(
            WrittenMail(to: ["Dana <dana@example.com>"], subject: "Hi", text: "Hello"), from: nil)
        let later = Date(timeIntervalSince1970: 1_800_000_000)
        try await catalog.send(draft, at: nil)
        try await catalog.send(draft, at: later)
        #expect(host.performed.sent.map(\.date) == [nil, later])
        #expect(host.performed.sent.first?.draft.to == [dana])
        #expect(host.performed.sent.first?.draft.accountID == account.id)
    }

    @Test func anEmailWithNoOneToGoToIsntSent() async throws {
        let host = host
        let catalog = Catalog(host: host)
        let draft = try catalog.newDraft(WrittenMail(text: "Hello"), from: nil)
        await #expect(throws: IntentError.self) { try await catalog.send(draft, at: nil) }
        #expect(host.performed.sent.isEmpty)
    }

    @Test func aReplyAnswersTheMessageChosenNotTheNewest() async throws {
        let reply = try await Catalog(host: host).answer(
            .replyAll, toMessage: "A1/t1/m1", with: WrittenMail(text: "On it"))
        #expect(reply.to == [dana])
        #expect(reply.cc.map(\.address) == ["avi@example.com"])
        #expect(reply.subject == "Re: Order")
        #expect(reply.body.plain == "On it")
        #expect(reply.quote?.plain?.contains("Body of m1") == true)
        #expect(reply.threadID == "t1")
    }

    @Test func aForwardGoesToThePeopleGiven() async throws {
        let forward = try await Catalog(host: host).answer(
            .forward, toMessage: "A1/t1/m3", with: WrittenMail(to: ["noa@example.com"], text: "FYI"))
        #expect(forward.to.map(\.address) == ["noa@example.com"])
        #expect(forward.subject == "Fwd: Order")
        try forward.checkReadyToSend()
    }

    @Test func answeringAMessageThatIsGoneFails() async {
        await #expect(throws: IntentError.self) {
            try await Catalog(host: host).answer(.reply, toMessage: "A1/t1/gone", with: WrittenMail())
        }
    }
}
