import Foundation
import MailCore
import Testing

struct MessageHeaderTests {
    private let dana = Contact(name: "Dana Levi", address: "dana@example.com")
    private let ori = Contact(name: "Ori", address: "ori@example.com")
    private let me = Contact(name: nil, address: "me@example.com")

    private func message(
        from: Contact, to: [Contact] = [], cc: [Contact] = [], bcc: [Contact] = [], replyTo: [Contact] = []
    ) -> Message {
        Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m"), threadID: "t", from: from, to: to,
            cc: cc,
            bcc: bcc, replyTo: replyTo, subject: "Hi", date: .distantPast, body: MessageBody(plain: "Hi"))
    }

    @Test func showsTheAddressBesideANamedSender() {
        #expect(MessageHeader(message(from: dana)).senderAddress == "dana@example.com")
    }

    @Test("A name that looks like an address still shows the real one")
    func showsTheAddressBesideANameThatLooksLikeOne() {
        let spoof = Contact(name: "support@bank.com", address: "x@phish.example")
        #expect(MessageHeader(message(from: spoof)).senderAddress == "x@phish.example")
    }

    @Test("A sender with no name shows the address once", arguments: [nil, ""])
    func showsTheAddressOnceWithoutAName(name: String?) {
        #expect(MessageHeader(message(from: Contact(name: name, address: "dana@example.com"))).senderAddress == nil)
    }

    @Test func showsAReplyToThatGoesSomewhereElse() {
        let other = Contact(name: "Dana", address: "inbox@elsewhere.example")
        #expect(MessageHeader(message(from: dana, replyTo: [other])).replyTo == [other])
    }

    @Test(
        "A Reply-To that only names the sender hides",
        arguments: [[], [Contact(name: nil, address: "DANA@example.com")]])
    func hidesAReplyToThatIsTheSender(replyTo: [Contact]) {
        #expect(MessageHeader(message(from: dana, replyTo: replyTo)).replyTo.isEmpty)
    }

    @Test func listsOnlyTheFieldsThatNameSomeone() {
        let header = MessageHeader(message(from: dana, to: [me], bcc: [ori]))
        #expect(header.fields == [.init(kind: .to, contacts: [me]), .init(kind: .bcc, contacts: [ori])])
        #expect(header.recipients == [me, ori])
    }
}
