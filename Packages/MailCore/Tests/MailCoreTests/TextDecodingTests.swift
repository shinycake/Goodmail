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

    @Test func addressListsSplitOnlyOutsideQuotesAndBrackets() {
        let list = Contact.list(
            parsing: #""Levi, Dana" <dana@example.com>, יעל כהן <yael@example.co.il>,bare@example.com"#)
        #expect(
            list == [
                Contact(name: "Levi, Dana", address: "dana@example.com"),
                Contact(name: "יעל כהן", address: "yael@example.co.il"),
                Contact(name: nil, address: "bare@example.com"),
            ])
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

    @Test func snippetEntitiesDecode() {
        #expect(HTMLEntities.decode("a &lt;b&gt; &#x41; &#65; &unknown; & done") == "a <b> A A &unknown; & done")
    }
}
