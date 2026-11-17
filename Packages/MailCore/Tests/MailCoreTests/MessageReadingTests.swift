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
        #expect(HTMLEntities.words(ofSnippet: "<div><b>Lunch?</b></div><div>Dana</div>") == "Lunch? Dana")
        #expect(HTMLEntities.words(ofSnippet: "I'll be late <3") == "I'll be late <3")
    }
}
