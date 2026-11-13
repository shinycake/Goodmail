import Foundation
import Testing

@testable import MailCore

struct MIMEParserTests {
    private func parse(_ lines: [String]) -> MIMEPart {
        MIMEPart(parsing: Data(lines.joined(separator: "\r\n").utf8))
    }

    /// Mixed, with an alternative body, a Hebrew-named PDF and an inline image, as Apple Mail sends.
    private static let mixed = [
        "From: =?UTF-8?B?16nXnNeV150=?= <dana@example.com>",
        "Subject: Report",
        "Content-Type: multipart/mixed;",
        "\tboundary=\"outer\"",
        "MIME-Version: 1.0",
        "",
        "This is a multi-part message in MIME format.",
        "--outer",
        "Content-Type: multipart/alternative; boundary=inner",
        "",
        "--inner",
        "Content-Type: text/plain; charset=utf-8",
        "Content-Transfer-Encoding: quoted-printable",
        "",
        "caf=C3=A9 and a long line that wraps=",
        " here",
        "--inner",
        "Content-Type: text/html; charset=\"utf-8\"",
        "Content-Transfer-Encoding: base64",
        "",
        "PHAgZGlyPSJhdXRvIj7Xqdec15XXnTwvcD4=",
        "--inner--",
        "",
        "--outer",
        "Content-Type: application/pdf",
        "Content-Disposition: attachment;",
        " filename*=utf-8''%D7%93%D7%95%D7%97.pdf",
        "Content-Transfer-Encoding: base64",
        "",
        "JVBERi0xLjQg",
        "ZmFrZQ==",
        "--outer",
        "Content-Type: image/png; name=\"logo.png\"",
        "Content-ID: <logo@x>",
        "Content-Disposition: inline",
        "Content-Transfer-Encoding: base64",
        "",
        "iVBORw==",
        "--outer--",
        "epilogue",
    ]

    @Test func partsAreNumberedLikeIMAPSections() {
        let message = parse(Self.mixed)
        #expect(message.partID == "")
        #expect(message.mimeType == "multipart/mixed")
        #expect(message.parts.map(\.partID) == ["1", "2", "3"])
        #expect(message.parts[0].parts.map(\.partID) == ["1.1", "1.2"])
        #expect(message.header("from") == "שלום <dana@example.com>", "headers are decoded")
    }

    @Test func transferEncodingsAreUndone() {
        let message = parse(Self.mixed)
        let alternative = message.parts[0]
        #expect(alternative.parts[0].data == Data("café and a long line that wraps here".utf8))
        #expect(alternative.parts[1].data == Data(#"<p dir="auto">שלום</p>"#.utf8))
        #expect(message.parts[1].data == Data("%PDF-1.4 fake".utf8))
    }

    @Test func contentReadsTheBodyAndAttachments() {
        let (body, attachments) = parse(Self.mixed).content()
        #expect(body.html == #"<p dir="auto">שלום</p>"#)
        #expect(body.plain == "café and a long line that wraps here")
        #expect(attachments.map(\.id) == ["2", "3"])
        #expect(attachments[0].filename == "דוח.pdf")
        #expect(attachments[0].mimeType == "application/pdf")
        #expect(attachments[0].size == 13)
        #expect(attachments[1].contentID == "logo@x")
        #expect(attachments[1].isInline)
        #expect(attachments[1].filename == "logo.png")
    }

    @Test func aSinglePartMessageIsPartOne() {
        let message = parse([
            "Subject: Hi", "Content-Type: text/plain; charset=windows-1255", "", "\u{5E9}", "",
        ])
        #expect(message.partID == "1")
        #expect(message.mimeType == "text/plain")
        #expect(message.charset == "windows-1255")
        #expect(message.content().body.plain == "\u{5E9}", "the line break ending the message isn't content")
    }

    @Test func aQuotedCharsetDecodesItsBytes() {
        var raw = Data("Content-Type: text/plain; charset=\"ISO-8859-1\"; format=flowed\r\n\r\ncaf".utf8)
        raw.append(0xE9)
        let message = MIMEPart(parsing: raw)
        #expect(message.charset == "ISO-8859-1")
        #expect(message.content().body.plain == "café")
    }

    @Test func aMessageWithoutContentTypeIsPlainText() {
        let message = MIMEPart(parsing: Data("Subject: x\n\nhello\n".utf8))
        #expect(message.mimeType == "text/plain")
        #expect(message.content().body.plain == "hello")
    }

    @Test func rfc2231ContinuationsAreJoined() {
        let value = HeaderValue(
            #"attachment; filename*0*=utf-8''%D7%93%D7%95; filename*1*=%D7%97; filename*2=".pdf"; size=13"#)
        #expect(value.value == "attachment")
        #expect(value.parameters["filename"] == "דוח.pdf")
        #expect(value.parameters["size"] == "13")
        #expect(HeaderValue(#"text/plain; name="a;b \"c\".txt""#).parameters["name"] == #"a;b "c".txt"#)
    }

    @Test func aCutOffMultipartKeepsItsLastPart() {
        let message = parse([
            "Content-Type: multipart/mixed; boundary=b", "", "--b", "Content-Type: text/plain", "", "partial",
        ])
        #expect(message.parts.count == 1)
        #expect(message.parts[0].data == Data("partial".utf8))
    }
}

struct EncodedWordsTests {
    @Test func encodedWordsDecodeAndJoinAcrossFolding() {
        #expect(EncodedWords.decode("=?UTF-8?B?16nXnNeV150=?= =?utf-8?b?16LXldec150=?=") == "שלוםעולם")
        #expect(EncodedWords.decode("Re: =?iso-8859-1?q?caf=E9_cr=E8me?= now") == "Re: café crème now")
        #expect(EncodedWords.decode("Plain = text?") == "Plain = text?")
    }
}
