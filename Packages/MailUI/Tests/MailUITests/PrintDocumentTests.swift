import Foundation
import MailCore
import Testing

@testable import MailUI

/// A printed message leads with its headers, escaped and reading their own way, over the body the reader sees.
struct PrintDocumentTests {
    private func message(body: MessageBody, cc: [Contact] = []) -> Message {
        Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m"), threadID: "t",
            from: Contact(name: "Dana <Ops>", address: "dana@example.com"),
            to: [Contact(name: nil, address: "me@example.com")], cc: cc, subject: "Plan",
            date: .distantPast, body: body)
    }

    @Test func theHeadersLeadTheSendersBody() throws {
        let html = PrintDocument.html(
            for: message(body: MessageBody(html: #"<html><head></head><body class="x"><p>Hi</p></body></html>"#)),
            subject: "Plan & budget", dateText: "14 Nov 2026", appearance: .light, allowsRemoteContent: false)

        let header = html.range(of: #"<header class="goodmail-print">"#)
        let paragraph = html.range(of: "<p>Hi</p>")
        #expect(html.contains(#"<body class="x"><header"#))
        #expect(try #require(header).lowerBound < (try #require(paragraph)).lowerBound)
        #expect(html.contains(#"<h1 dir="auto">Plan &amp; budget</h1>"#))
        #expect(html.contains("Dana &lt;Ops&gt; &lt;dana@example.com&gt;"))
        #expect(html.contains("me@example.com"))
        #expect(html.contains("Content-Security-Policy"))
    }

    @Test func laterMessagesSkipTheSubjectAndEmptyLines() {
        let header = PrintDocument.header(
            for: message(body: MessageBody(plain: "Hi")), subject: nil, dateText: "Today")
        #expect(!header.contains("<h1"))
        #expect(!header.contains("Cc:"))
        #expect(header.contains("Today"))
    }

    @Test func aBodyWithoutABodyTagStillGetsItsHeaders() {
        let document = PrintDocument.inject(body: "<header></header>", into: "<html><head></head><p>Hi</p></html>")
        #expect(document == "<html><head></head><header></header><p>Hi</p></html>")
    }

    @Test func aForcedAppearanceAnswersEveryColorSchemeQuery() {
        let sender = "@media (prefers-color-scheme: dark) { a } @media (PREFERS-COLOR-SCHEME:light) { b }"
        #expect(
            ForcedAppearance.dark.apply(to: sender)
                == "@media (min-width: 0px) { a } @media (max-width: 0px) { b }")
        #expect(
            ForcedAppearance.light.apply(to: sender)
                == "@media (max-width: 0px) { a } @media (min-width: 0px) { b }")
    }
}
