import Foundation
import MailCore
import Testing

/// Which part of a body is read, and as what, so markup never reaches a reader as text.
struct MessageReadingTests {
    @Test func plainWordsReadAsPlain() {
        let body = MessageBody(html: "<p>Lunch?</p>", plain: "Lunch?")
        #expect(body.reading == .plain("Lunch?"))
    }

    @Test func anEmptyPlainPartFallsBackToTheHTML() {
        #expect(MessageBody(html: "<p>Lunch?</p>", plain: " \n").reading == .html("<p>Lunch?</p>"))
        #expect(MessageBody().reading == .empty)
    }

    /// Some senders put the HTML in the plain part, and a message without a Content-Type reads as plain.
    @Test(arguments: [
        "<!DOCTYPE html><html><body>Lunch?</body></html>",
        "<html>\n<head></head><body>Lunch?</body></html>",
        "<div dir=\"rtl\">שלום</div><div><br></div><div>Lunch?</div>",
        "<p>Lunch?</p>\n<p>Dana</p><br>",
    ])
    func markupInThePlainPartReadsAsHTML(_ plain: String) {
        #expect(MessageBody(plain: plain).reading == .html(plain))
        #expect(MessageBody(html: "<p>Real</p>", plain: plain).reading == .html("<p>Real</p>"))
    }

    @Test(arguments: [
        "Use a <div> there, not a table.",
        "I'll be 5 min late <3",
        "a < b and c > d",
    ])
    func plainWordsThatMentionATagStayPlain(_ plain: String) {
        #expect(MessageBody(plain: plain).reading == .plain(plain))
    }

    @Test func textIsTheWordsOfWhicheverPartReads() {
        #expect(MessageBody(plain: "<html><body><p>Lunch?</p><p>Dana</p></body></html>").text == "Lunch?\nDana")
    }

    @Test func aSnippetOfMarkupBecomesItsWords() {
        #expect(SnippetText.words(of: "<div><b>Lunch?</b></div><div>Dana</div>") == "Lunch? Dana")
        #expect(SnippetText.words(of: "I'll be late <3") == "I'll be late <3")
    }

    /// Marketing mail pads its preheader with invisible characters so the preview stops after it.
    @Test func aSnippetLosesPreheaderFiller() {
        let filler = String(repeating: "\u{034F} \u{200C}\u{00A0}\u{00AD}\u{200B}\u{FEFF}", count: 40)
        #expect(SnippetText.words(of: "Our only sale of the year! \(filler)") == "Our only sale of the year!")
        #expect(
            SnippetText.words(of: "<p>Sale!</p><p>\(filler)</p><div>Ends Sunday</div>") == "Sale! Ends Sunday")
    }

    @Test(arguments: [
        "Family \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} trip",  // A joiner inside an emoji
        "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}",  // A non-joiner inside a Persian word
        "\u{05E9}\u{05DC}\u{05D5}\u{05DD} \u{200F}(2)",  // A right-to-left mark in Hebrew
        "\u{0915}\u{094D}\u{200D} x",  // A joiner ending a Devanagari half-form
    ])
    func aSnippetKeepsCharactersThatDoSomething(text: String) {
        #expect(SnippetText.words(of: text) == text)
    }

    @Test func styledTextKeepsTheWholeBodyWithOneBlankLineBetweenBlocks() {
        let html =
            "<table><tr><td><b>Sale</b></td></tr></table><p></p><p> </p><p>Ends <a href=\"https://example.com\">Sunday</a></p>"
        var expected = StyledText()
        expected.append("Sale", style: .bold)
        expected.append("\n\nEnds ")
        expected.append("Sunday", link: URL(string: "https://example.com"))
        #expect(MessageBody(html: html).styledText == expected)
        #expect(MessageBody(plain: "Hi\r\n\r\n\r\n\r\nDana\r\n\r\n").styledText.plain == "Hi\n\nDana")
        #expect(MessageBody().styledText.isEmpty)
    }

    @Test func styledTextLeavesOutWhatANewsletterHides() {
        let html =
            "<div style=\"display: none; max-height: 0\">Don't miss our sale \u{200C}\u{200C} \u{200C}</div>"
            + "<span style='DISPLAY:NONE'>\u{034F} \u{00AD}</span><p>\u{200C} \u{200C}</p><p>Hello 👨‍👩‍👧</p>"
        #expect(MessageBody(html: html).styledText.plain == "Hello 👨‍👩‍👧")
    }

    @Test func styledTextReadsTheHTMLsLineBreaksFromItsTagsAlone() {
        let html = "<p>A paragraph Outlook\r\n  wraps in its source.</p>\n<p><pre>Kept\non two lines</pre></p>"
        #expect(
            MessageBody(html: html, plain: "A paragraph").styledText.plain
                == "A paragraph Outlook wraps in its source.\nKept\non two lines")
    }

    @Test func styledTextFallsBackToThePlainPartWhenTheHTMLHoldsNoWords() {
        #expect(
            MessageBody(html: "<img src=\"cid:card\">", plain: "Happy birthday!").styledText.plain == "Happy birthday!")
    }
}
