import Foundation
import Testing

@testable import MailCore

/// A list's `List-Unsubscribe` headers become the one way the reader leaves it that asks least of them.
struct UnsubscribeTests {
    @Test func oneClickWinsWhenTheListMarksItsHTTPSLink() {
        let unsubscribe = Unsubscribe(
            listUnsubscribe: "<mailto:leave@list.example.com?subject=unsubscribe>, <https://list.example.com/u/42>",
            post: "List-Unsubscribe=One-Click")
        #expect(unsubscribe == .oneClick(URL(string: "https://list.example.com/u/42")!))
    }

    @Test func withoutTheOneClickMarkerAMailComesBeforeAPage() {
        let unsubscribe = Unsubscribe(
            listUnsubscribe: "<https://list.example.com/u/42>, <mailto:leave@list.example.com?subject=Remove%20me>",
            post: nil)
        #expect(unsubscribe == .mail(Unsubscribe.Mailto(to: ["leave@list.example.com"], subject: "Remove me")))
    }

    @Test(
        arguments: [
            ("<https://list.example.com/u/42>", nil),
            ("<http://list.example.com/u/42>", nil),
            // One-click needs HTTPS; a plain HTTP link is only a page.
            ("<http://list.example.com/u/42>", "List-Unsubscribe=One-Click"),
        ] as [(String, String?)])
    func aLinkAloneIsAPageToOpen(header: String, post: String?) throws {
        let unsubscribe = try #require(Unsubscribe(listUnsubscribe: header, post: post))
        guard case .page(let url) = unsubscribe else {
            Issue.record("Expected a page, got \(unsubscribe)")
            return
        }
        #expect(url.host() == "list.example.com")
    }

    @Test func foldingInsideTheBracketsAndCommentsAreIgnored() {
        let unsubscribe = Unsubscribe(
            listUnsubscribe: "(Use this) <https://list.example.com/\r\n u/42>", post: "List-Unsubscribe=One-Click")
        #expect(unsubscribe == .oneClick(URL(string: "https://list.example.com/u/42")!))
    }

    @Test(arguments: ["", "no brackets here", "<ftp://list.example.com/u>", "<mailto:?subject=nobody>"])
    func aHeaderWithNothingUsableOffersNothing(header: String) {
        #expect(Unsubscribe(listUnsubscribe: header, post: "List-Unsubscribe=One-Click") == nil)
    }

    @Test func aMailtoKeepsEveryAddressItsSubjectAndBody() throws {
        let mailto = try #require(
            Unsubscribe.Mailto(URL(string: "mailto:a@list.example.com?to=b@list.example.com&body=leave%20please")!))
        #expect(mailto == Unsubscribe.Mailto(to: ["a@list.example.com", "b@list.example.com"], body: "leave please"))
    }

    @Test func aMessageReadsItsListHeaders() {
        let raw = Data(
            """
            From: News <news@example.com>\r
            Subject: Weekly\r
            List-Unsubscribe: <https://example.com/leave>\r
            List-Unsubscribe-Post: List-Unsubscribe=One-Click\r
            Content-Type: text/plain\r
            \r
            Hi\r

            """.utf8)
        let message = Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m"), threadID: "t",
            mime: MIMEPart(parsing: raw), date: .distantPast, snippet: "", labelIDs: [])
        #expect(message.unsubscribe == .oneClick(URL(string: "https://example.com/leave")!))
    }

    @Test func aMessageCachedBeforeListHeadersDecodesWithoutThem() throws {
        var message = Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m"), threadID: "t",
            from: Contact(name: nil, address: "news@example.com"), subject: "Weekly", date: .distantPast,
            body: MessageBody(plain: "Hi"), unsubscribe: .page(URL(string: "https://example.com/leave")!))
        let encoded = try JSONEncoder().encode(message)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["unsubscribe"] = nil
        let old = try JSONDecoder().decode(Message.self, from: JSONSerialization.data(withJSONObject: object))
        message.unsubscribe = nil
        #expect(old == message)
    }

    @Test func theMessageBodyIsEscapedForItsHTMLPart() {
        let draft = ListUnsubscriber.draft(
            for: Unsubscribe.Mailto(to: ["l@example.com"], subject: "Stop", body: "a<b>&\nc"),
            account: AccountID(rawValue: "a"))
        #expect(draft.subject == "Stop")
        #expect(draft.body == MessageBody(html: "a&lt;b&gt;&amp;<br>c", plain: "a<b>&\nc"))
    }

    @Test(arguments: [
        "mailto:a@list.example.com%0D%0ABcc:victim@example.com",
        "mailto:x?to=a@list.example.com%0ABcc:victim@example.com",
        "mailto:a%20b@list.example.com",
        "mailto:%3Ca@list.example.com%3E",
    ])
    func anAddressHidingHeadersOrPunctuationIsDropped(uri: String) throws {
        #expect(Unsubscribe.Mailto(try #require(URL(string: uri))) == nil)
    }

    @Test func aSubjectWithLineBreaksStaysOnOneLine() throws {
        let mailto = try #require(
            Unsubscribe.Mailto(URL(string: "mailto:a@list.example.com?subject=leave%0D%0ABcc:%20victim@example.com")!))
        #expect(mailto.subject == "leave  Bcc: victim@example.com")
    }

    @Test func theWriterKeepsEveryHeaderValueOnItsLine() {
        let draft = Draft(
            accountID: AccountID(rawValue: "a"),
            to: [Contact(name: "Dana\r\nX-Evil: 1", address: "dana@example.com\r\nBcc: victim@example.com")],
            subject: "Hi\r\nBcc: victim@example.com")
        let raw = String(
            decoding: MIMEWriter.message(
                for: draft, from: Contact(name: nil, address: "me@example.com"), date: .distantPast, messageID: "m@x"),
            as: UTF8.self)
        let headers = raw.components(separatedBy: "\r\n\r\n")[0].components(separatedBy: "\r\n")
        #expect(!headers.contains { $0.hasPrefix("Bcc:") || $0.hasPrefix("X-Evil:") })
    }
}
