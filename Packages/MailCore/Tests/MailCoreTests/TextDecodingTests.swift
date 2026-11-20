import Foundation
import Testing

@testable import MailCore

#if os(Linux)
    private let isLinux = true
#else
    private let isLinux = false
#endif

struct TextDecodingTests {
    @Test func validUTF8WinsOverADeclaredLegacyCharset() {
        // What Gmail returns for a windows-1255 message: UTF-8 bytes, original label.
        #expect(TextDecoding.string(from: Data("שלום".utf8), declaredCharset: "windows-1255") == "שלום")
    }

    @Test(.disabled(if: isLinux, "Linux's Foundation has no windows-1255"))
    func legacyBytesUseTheDeclaredCharset() {
        // What IMAP will return: the original bytes.
        let windows1255 = Data([0xF9, 0xEC, 0xE5, 0xED])
        #expect(TextDecoding.string(from: windows1255, declaredCharset: "windows-1255") == "שלום")
        #expect(TextDecoding.string(from: windows1255, declaredCharset: "ISO-8859-8-I") == "שלום")
    }

    @Test func unknownCharsetFallsBackToLatin1() {
        #expect(TextDecoding.string(from: Data([0x63, 0x61, 0x66, 0xE9]), declaredCharset: "x-unknown") == "café")
    }

    /// IMAP fetches only the start of a message for its snippet, which can end partway through a character.
    @Test(arguments: [nil, "utf-8"], [("\u{200C}", 1), ("\u{200C}", 2), ("\u{1F6EB}", 1), ("\u{1F6EB}", 3)])
    func utf8CutPartwayThroughACharacterKeepsTheWholeOnes(charset: String?, cut: (last: String, bytes: Int)) {
        let whole = Data("Sale! \u{034F}\u{00A0}\(cut.last)".utf8)
        let text = TextDecoding.string(from: whole.dropLast(cut.bytes), declaredCharset: charset)
        #expect(text == "Sale! \u{034F}\u{00A0}")
    }

    @Test func latin1EndingInALetterKeepsIt() {
        // 0xE9 starts a three-byte UTF-8 character, but nothing before it is UTF-8.
        #expect(TextDecoding.string(from: Data([0x63, 0x61, 0x66, 0xE9]), declaredCharset: "iso-8859-1") == "café")
    }

    @Test func mixedPartsKeepEveryTextBodyAndListTheRest() {
        let root = MIMEPart(
            partID: "",
            mimeType: "multipart/mixed",
            parts: [
                MIMEPart(partID: "0", mimeType: "text/plain", data: Data("first".utf8)),
                MIMEPart(
                    partID: "1", mimeType: "text/plain",
                    headers: [("Content-Disposition", "attachment; filename=notes.txt")], filename: "notes.txt",
                    size: 12, fetchToken: "t1"),
                MIMEPart(partID: "2", mimeType: "text/plain", data: Data("second".utf8)),
            ]
        )
        let content = root.content()
        #expect(content.body.plain == "first\n\nsecond")
        #expect(content.attachments.map(\.filename) == ["notes.txt"])
    }

    @Test func signatureHTMLKeepsItsLines() {
        #expect(HTMLEntities.plainText(fromHTML: "Dana<br>CEO<br/>  <b>Goodmail</b>") == "Dana\nCEO\nGoodmail")
        #expect(HTMLEntities.plainText(fromHTML: "<p>One</p><p>Two</p>") == "One\nTwo")
        #expect(HTMLEntities.plainText(fromHTML: "") == "")
    }

    @Test func bodyHTMLLosesWhatIsNotItsWords() {
        let html = """
            <html><head><title>Newsletter</title><style>p { color: red; }</style></head>
            <body><!-- tracking --><p>שלום Dana</p><script>var x = 1;</script><p>See you</p></body></html>
            """
        #expect(HTMLEntities.plainText(fromHTML: html) == "שלום Dana\nSee you")
    }

    /// The start of a message, as IMAP fetches it for a snippet, can end inside its head or a tag.
    @Test(arguments: [
        ("<html><head><title>Ready</title><STYLE type=\"text/css\">A { text-decoration: none; } A:link { co", ""),
        ("<HTML><HEAD><TITLE>Ready</TITLE></HEAD><BODY><P>Build 18 is ready</P><TABLE wid", "Build 18 is ready"),
        ("<p>Hi</p><!-- a long comment that never ends", "Hi"),
    ])
    func htmlCutShortLosesWhatIsNotItsWords(html: String, words: String) {
        #expect(HTMLEntities.plainText(fromHTML: html) == words)
    }

    @Test func stylesOutsideTheHeadInAnyCaseAreNotWords() {
        let html = "<Style>A:link { color: #0088CC; }</STYLE><div>Goodmail 1.0 (18) is ready</div>"
        #expect(HTMLEntities.plainText(fromHTML: html) == "Goodmail 1.0 (18) is ready")
    }

    @Test func snippetEntitiesDecode() {
        #expect(HTMLEntities.decode("a &lt;b&gt; &#x41; &#65; &unknown; & done") == "a <b> A A &unknown; & done")
    }
}
