import Foundation
import Testing

@testable import MailCore

struct MessageMIMETests {
    private static let raw = Data(
        """
        From: Me <me@example.com>\r
        To: Dana <dana@example.com>, yossi@example.co.il\r
        Bcc: boss@example.com\r
        Reply-To: replies@example.com\r
        Subject: =?UTF-8?B?16nXnNeV150=?=\r
        Message-ID: <a1@example.com>\r
        References: <r1@example.com>\r
         <r2@example.com><r3@example.com> (comment)\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        Hello\r

        """.utf8)

    private func message(labels: Set<String>) -> Message {
        Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m"), threadID: "t",
            mime: MIMEPart(parsing: Self.raw), date: Date(timeIntervalSince1970: 0), snippet: "Hello",
            labelIDs: labels)
    }

    @Test func peopleSubjectAndThreadingComeFromTheHeaders() {
        let message = message(labels: [SystemLabel.sent])
        #expect(message.from == Contact(name: "Me", address: "me@example.com"))
        #expect(message.to.map(\.address) == ["dana@example.com", "yossi@example.co.il"])
        #expect(message.replyTo.map(\.address) == ["replies@example.com"])
        #expect(message.subject == "שלום")
        #expect(message.internetMessageID == "a1@example.com")
        #expect(message.references == ["r1@example.com", "r2@example.com", "r3@example.com"])
        #expect(message.body.plain == "Hello")
    }

    @Test func onlyADraftShowsItsBcc() {
        #expect(message(labels: [SystemLabel.sent]).bcc.isEmpty)
        #expect(message(labels: [SystemLabel.draft]).bcc.map(\.address) == ["boss@example.com"])
    }
}
