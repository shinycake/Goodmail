import Foundation
import Testing

@testable import MailCore

/// What a shortcut writes, put into a new message, a reply or a forward.
struct WrittenMailTests {
    private let account = AccountID(rawValue: "a1")

    @Test func aNewMessageTakesEverythingWritten() throws {
        var draft = Draft(accountID: account)
        try draft.add(
            WrittenMail(
                to: ["Dana <dana@example.com>, avi@example.com"], cc: ["noa@example.com; ido@example.com"],
                bcc: ["me@example.com"], subject: "  Orders ", text: "Line one\nשורה שתיים"))
        #expect(
            draft.to == [
                Contact(name: "Dana", address: "dana@example.com"), Contact(name: nil, address: "avi@example.com"),
            ])
        #expect(draft.cc.map(\.address) == ["noa@example.com", "ido@example.com"])
        #expect(draft.bcc.map(\.address) == ["me@example.com"])
        #expect(draft.subject == "Orders")
        #expect(draft.body.plain == "Line one\nשורה שתיים")
        #expect(draft.body.html == #"<div dir="auto">Line one</div><div dir="auto">שורה שתיים</div>"#)
        try draft.checkReadyToSend()
    }

    @Test func aReplyKeepsItsSubjectQuoteAndRecipients() throws {
        var reply = Draft(
            accountID: account, to: [Contact(name: nil, address: "dana@example.com")], subject: "Re: Orders",
            quote: MessageBody(plain: "> Hi"), threadID: "t1")
        try reply.add(WrittenMail(cc: ["avi@example.com"], text: "Thanks"))
        #expect(reply.subject == "Re: Orders")
        #expect(reply.to.map(\.address) == ["dana@example.com"])
        #expect(reply.cc.map(\.address) == ["avi@example.com"])
        #expect(reply.quote == MessageBody(plain: "> Hi"))
        #expect(reply.body.plain == "Thanks")
        #expect(reply.threadID == "t1")
    }

    @Test func aRecipientThatIsntAnAddressLeavesTheDraftAsItWas() {
        var draft = Draft(accountID: account, subject: "Kept")
        #expect(throws: WrittenMailError.notAnAddress("dana")) {
            try draft.add(WrittenMail(to: ["avi@example.com", "dana"], subject: "Changed"))
        }
        #expect(draft.to.isEmpty)
        #expect(draft.subject == "Kept")
    }

    @Test func aMessageNeedsSomeoneToGoTo() {
        #expect(throws: WrittenMailError.noRecipients) { try Draft(accountID: account).checkReadyToSend() }
    }
}
