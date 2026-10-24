import Foundation
import MailCore
import Testing

@testable import MailCore

struct DraftTests {
    private let account = AccountID(rawValue: "a")
    private let me = "me@example.com"
    private let utc = TimeZone(identifier: "UTC")!
    private let english = Locale(identifier: "en_US")

    private func message(
        from: Contact, to: [Contact], cc: [Contact] = [], replyTo: [Contact] = [], subject: String = "Plan"
    ) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: "m2"), threadID: "t1", from: from, to: to, cc: cc,
            replyTo: replyTo, subject: subject, date: Date(timeIntervalSince1970: 1_791_800_000),
            body: MessageBody(html: "<html><body><p>Ship it?</p></body></html>", plain: "Ship it?\n\nDana"),
            internetMessageID: "m2@example.com", references: ["m1@example.com"])
    }

    private let dana = Contact(name: "Dana Levi", address: "dana@example.com")
    private let avi = Contact(name: "Avi", address: "avi@example.com")

    @Test func replyGoesToTheSenderAndThreads() {
        let draft = Draft.reply(
            to: message(from: dana, to: [Contact(name: nil, address: me), avi]), all: false, accountEmail: me,
            locale: english, timeZone: utc)
        #expect(draft.to == [dana])
        #expect(draft.cc.isEmpty)
        #expect(draft.subject == "Re: Plan")
        #expect(draft.threadID == "t1")
        #expect(draft.inReplyTo == "m2@example.com")
        #expect(draft.references == ["m1@example.com", "m2@example.com"])
    }

    @Test func replyAllKeepsEveryoneButMe() {
        let draft = Draft.reply(
            to: message(from: dana, to: [Contact(name: "Me", address: "ME@example.com"), avi], cc: [dana]),
            all: true, accountEmail: me, locale: english, timeZone: utc)
        #expect(draft.to == [dana])
        #expect(draft.cc == [avi], "the sender isn't repeated in Cc, and I'm left out")
    }

    @Test func replyHonorsReplyToAndMyOwnMessages() {
        let list = Contact(name: nil, address: "list@example.com")
        #expect(
            Draft.reply(to: message(from: dana, to: [avi], replyTo: [list]), all: false, accountEmail: me).to == [list])
        let mine = message(from: Contact(name: nil, address: me), to: [avi])
        #expect(Draft.reply(to: mine, all: false, accountEmail: me).to == [avi], "a reply to myself goes to them")
    }

    @Test func subjectsArentPrefixedTwice() {
        #expect(
            Draft.reply(to: message(from: dana, to: [], subject: "RE: Plan"), all: false, accountEmail: me)
                .subject == "RE: Plan")
        #expect(Draft.forward(message(from: dana, to: [], subject: "Fw: Plan")).subject == "Fw: Plan")
        #expect(Draft.forward(message(from: dana, to: [])).subject == "Fwd: Plan")
    }

    @Test func theQuoteCarriesTheOriginalAndItsAttribution() throws {
        let draft = Draft.reply(
            to: message(from: dana, to: []), all: false, accountEmail: me, locale: english, timeZone: utc)
        let quote = try #require(draft.quote)
        #expect(quote.html?.contains("Dana Levi &lt;dana@example.com&gt; wrote:") == true)
        #expect(quote.html?.contains("<blockquote class=\"gmail_quote\" type=\"cite\"") == true)
        #expect(quote.html?.contains("<p>Ship it?</p></blockquote>") == true, "the original's body, not its document")
        #expect(quote.plain?.hasSuffix("> Ship it?\n>\n> Dana") == true)
    }

    @Test func forwardsKeepTheThreadAndListTheOriginalHeaders() throws {
        let draft = Draft.forward(message(from: dana, to: [avi]), locale: english, timeZone: utc)
        #expect(draft.to.isEmpty)
        #expect(draft.threadID == "t1")
        #expect(draft.inReplyTo == nil)
        let plain = try #require(draft.quote?.plain)
        #expect(plain.contains("From: Dana Levi <dana@example.com>"))
        #expect(plain.contains("To: Avi <avi@example.com>"))
    }
}

struct MIMEWriterTests {
    private let draft = Draft(
        accountID: AccountID(rawValue: "a"),
        to: [Contact(name: "Dana Levi", address: "dana@example.com"), Contact(name: "יעל כהן", address: "y@x.il")],
        bcc: [Contact(name: nil, address: "hidden@example.com")],
        subject: "Re: סיכום פגישה",
        body: MessageBody(html: "<div dir=\"auto\">Thanks!</div>", plain: "Thanks!"),
        quote: MessageBody(html: "<blockquote>old</blockquote>", plain: "> old"),
        threadID: "t1", inReplyTo: "m2@example.com", references: ["m1@example.com", "<m2@example.com>"])

    private func written() -> String {
        String(
            decoding: MIMEWriter.message(
                for: draft, from: Contact(name: "Tester, QA", address: "me@example.com"),
                date: Date(timeIntervalSince1970: 0), messageID: "id1@goodmail.app", boundary: "B"),
            as: UTF8.self)
    }

    @Test func headersAreAsciiAndThreaded() {
        let text = written()
        let headers = text.components(separatedBy: "\r\n\r\n")[0]
        #expect(headers.unicodeScalars.allSatisfy { $0.isASCII })
        #expect(headers.contains("From: \"Tester, QA\" <me@example.com>"))
        #expect(headers.contains("Date: Thu, 01 Jan 1970 00:00:00 +0000"))
        #expect(headers.contains("To: Dana Levi <dana@example.com>, =?UTF-8?B?"))
        #expect(headers.contains("Bcc: hidden@example.com"))
        #expect(headers.contains("In-Reply-To: <m2@example.com>"))
        #expect(headers.contains("References: <m1@example.com> <m2@example.com>"))
        #expect(headers.contains("Content-Type: multipart/alternative; boundary=\"B\""))
    }

    @Test func encodedWordsRoundTripAndStayShort() throws {
        let long = String(repeating: "שלום עולם ", count: 8)
        let encoded = MIMEWriter.encodedWords(long)
        let words = encoded.components(separatedBy: "\r\n ")
        #expect(words.allSatisfy { $0.count <= 75 })
        let decoded = try words.map { word in
            let base64 = word.dropFirst("=?UTF-8?B?".count).dropLast(2)
            return try #require(Data(base64Encoded: String(base64)).map { String(decoding: $0, as: UTF8.self) })
        }
        #expect(decoded.joined() == long)
        #expect(MIMEWriter.encodedWords("Plain") == "Plain")
    }

    @Test func bothPartsCarryTheBodyAndTheQuote() throws {
        let parts = written().components(separatedBy: "--B")
        #expect(parts.count == 4, "preamble, plain, html, closing")
        func body(_ part: String) throws -> String {
            let encoded = part.components(separatedBy: "\r\n\r\n")[1].replacingOccurrences(of: "\r\n", with: "")
            return String(decoding: try #require(Data(base64Encoded: encoded)), as: UTF8.self)
        }
        #expect(try body(parts[1]) == "Thanks!\n\n> old")
        #expect(try body(parts[2]).contains("<body><div dir=\"auto\">Thanks!</div><br><blockquote>old</blockquote>"))
    }

    @Test func filesGoInAMixedPartAfterTheText() throws {
        var draft = draft
        let pdf = Data((0..<200).map { UInt8($0 % 256) })
        draft.attachments = [
            DraftAttachment(filename: "Report Q3.pdf", mimeType: "application/pdf", data: pdf),
            DraftAttachment(filename: "סיכום.txt", mimeType: "text/plain", data: Data("hi".utf8)),
        ]
        let text = String(
            decoding: MIMEWriter.message(
                for: draft, from: Contact(name: nil, address: "me@example.com"), date: Date(timeIntervalSince1970: 0),
                messageID: "id1@goodmail.app", boundary: "B"),
            as: UTF8.self)
        #expect(text.unicodeScalars.allSatisfy { $0.isASCII })
        let headers = text.components(separatedBy: "\r\n\r\n")[0]
        #expect(headers.hasSuffix("Content-Type: multipart/mixed; boundary=\"B\""))

        let parts = text.components(separatedBy: "--B\r\n")
        #expect(parts.count == 4, "preamble, the text, two files")
        #expect(parts[1].hasPrefix("Content-Type: multipart/alternative; boundary=\"B-alt\""))
        #expect(parts[1].contains("--B-alt--"))
        #expect(parts[2].contains("Content-Type: application/pdf; name=\"Report Q3.pdf\""))
        #expect(parts[2].contains("Content-Disposition: attachment; filename=\"Report Q3.pdf\""))
        let encoded = parts[2].components(separatedBy: "\r\n\r\n")[1].replacingOccurrences(of: "\r\n", with: "")
        #expect(Data(base64Encoded: encoded) == pdf)
        #expect(parts[3].contains("filename*=UTF-8''%D7%A1%D7%99%D7%9B%D7%95%D7%9D.txt"))
        #expect(text.hasSuffix("--B--\r\n"))
    }

    @Test func draftsSavedBeforeAttachmentsStillDecode() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        json["attachments"] = nil
        let decoded = try JSONDecoder().decode(Draft.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == draft)
    }
}
