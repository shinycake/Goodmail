import Foundation
import MailCore
import Testing

@testable import MailUI

struct MessageDocumentTests {
    @Test func plainTextIsEscapedAndQuotesNestByDepth() {
        let html = MessageDocument.plainToHTML("Hi <team>\n\n> On Monday:\n>> Ship it?\nThanks")
        #expect(html.contains(#"<div dir="auto">Hi &lt;team&gt;</div><br>"#))
        #expect(html.contains(#"<blockquote class="goodmail-quote"><div dir="auto">On Monday:</div>"#))
        #expect(
            html.contains(
                #"<blockquote class="goodmail-quote"><div dir="auto">Ship it?</div></blockquote></blockquote>"#))
        #expect(html.hasSuffix(#"<div dir="auto">Thanks</div>"#))
    }

    @Test func ourStylesGoFirstInTheSendersHead() {
        let html = MessageDocument.html(
            for: MessageBody(html: "<html><head><style>p{}</style></head><body>x</body></html>"))
        let ours = html.range(of: "-webkit-text-size-adjust")!
        let theirs = html.range(of: "p{}")!
        #expect(ours.lowerBound < theirs.lowerBound)
    }

    @Test func bareFragmentsGetADocument() {
        let html = MessageDocument.html(for: MessageBody(html: "<p>Hello</p>"))
        #expect(html.hasPrefix("<!doctype html><html><head>"))
        #expect(html.hasSuffix("<body><p>Hello</p></body></html>"))
    }
}

@MainActor
struct ThreadViewModelTests {
    private let account = AccountID(rawValue: "a")

    private func message(_ id: String, unread: Bool, minutes: Double) -> Message {
        var labels: Set<String> = ["INBOX"]
        if unread { labels.insert("UNREAD") }
        return Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t",
            from: Contact(name: "Dana", address: "dana@example.com"), subject: "Plan",
            date: Date(timeIntervalSince1970: minutes * 60), labelIDs: labels, body: MessageBody(plain: id))
    }

    @Test func unreadMessagesAndTheNewestOpenAsCards() {
        let messages = [
            message("1", unread: false, minutes: 1), message("2", unread: true, minutes: 2),
            message("3", unread: false, minutes: 3), message("4", unread: false, minutes: 4),
        ]
        #expect(ThreadViewModel.initiallyExpanded(messages) == [messages[1].id, messages[3].id])
    }

    @Test func theLastOpenCardCannotBeClosed() {
        let messages = [message("1", unread: false, minutes: 1)]
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Plan", snippet: "",
                sender: messages[0].from, date: .now, isUnread: false, messageCount: 1, labelIDs: []),
            accountEmail: "me@example.com", accountColor: .blue,
            messages: { AsyncThrowingStream { $0.finish() } }, load: {}, attachmentData: { _, _ in Data() })
        model.toggle(messages[0].id)
        #expect(model.expanded == [messages[0].id])
        model.toggle(messages[0].id)
        #expect(model.expanded == [messages[0].id], "a thread always shows at least one card")
    }
}
