import Foundation
import Testing

@testable import MailCore

/// A conversation as plain text, for notes, chats and anything that takes words rather than files.
struct ConversationTextTests {
    private let labels = ConversationText.Labels(from: "From:", to: "To:", cc: "Cc:", date: "Date:")

    private func message(
        _ id: String, from: Contact, to: [Contact] = [], cc: [Contact] = [], body: MessageBody
    ) -> Message {
        Message(
            id: Message.ID(accountID: AccountID(rawValue: "acct"), messageID: id), threadID: "t", from: from, to: to,
            cc: cc,
            subject: "Plan", date: .now, snippet: "", labelIDs: [], body: body)
    }

    @Test func theSubjectLeadsThenEachMessagesHeadersAndBody() {
        let text = ConversationText.text(
            for: [
                message(
                    "1", from: Contact(name: "Dana Levi", address: "dana@example.com"),
                    to: [Contact(name: nil, address: "avi@example.com")], body: MessageBody(plain: "Thursday?\n")),
                message(
                    "2", from: Contact(name: nil, address: "avi@example.com"),
                    cc: [Contact(name: "Yael", address: "y@e.com")],
                    body: MessageBody(plain: "Works for me.")),
            ],
            subject: "Plan for Thursday", labels: labels, dateText: { $0.id.messageID == "1" ? "Monday" : "Tuesday" })
        #expect(
            text == """
                Plan for Thursday

                From: Dana Levi <dana@example.com>
                To: avi@example.com
                Date: Monday

                Thursday?

                ――――――――――

                From: avi@example.com
                Cc: Yael <y@e.com>
                Date: Tuesday

                Works for me.

                """)
    }

    @Test func anHTMLOnlyBodyBecomesItsWords() {
        let text = ConversationText.text(
            for: [
                message(
                    "1", from: Contact(name: nil, address: "a@b.c"),
                    body: MessageBody(html: "<style>p{}</style><p>Hello&nbsp;there</p><p>Bye</p>"))
            ], subject: "S", labels: labels, dateText: { _ in "Now" })
        #expect(text.hasSuffix("Date: Now\n\nHello\u{A0}there\nBye\n"))
    }
}
