import Foundation
import MailCore
import Testing

struct ReplyTextTests {
    private func plain(_ text: String) -> [ReplyText.Segment] {
        ReplyText(body: MessageBody(plain: text)).segments
    }

    private func html(_ markup: String) -> [ReplyText.Segment] {
        ReplyText(body: MessageBody(html: markup)).segments
    }

    @Test func aMessageWithoutHistoryIsAllNewText() {
        #expect(plain("Lunch at noon?\n\nDana") == [.text("Lunch at noon?\n\nDana")])
    }

    @Test(arguments: [
        "Sounds good.\n\nOn Mon, Oct 12, 2026 at 9:10 AM Dana Levi <dana@example.com> wrote:\n> Lunch at noon?\n>\n> Dana",
        "Sounds good.\n\nOn Mon, Oct 12, 2026 at 9:10 AM Dana Levi <\ndana@example.com> wrote:\n\n> Lunch at noon?",
        "Sounds good.\n\nבתאריך יום ב׳, 12 באוק׳ 2026 ב-9:10 מאת Dana Levi <dana@example.com>:\n> Lunch at noon?",
        "Sounds good.\n\nLe lun. 12 oct. 2026 à 09:10, Dana Levi <dana@example.com> a écrit :\n> Lunch at noon?",
        "Sounds good.\n\n-----Original Message-----\nFrom: Dana Levi\nSent: Monday\nSubject: Lunch\n\nLunch at noon?",
        "Sounds good.\n\n________________________________\nFrom: Dana Levi <dana@example.com>\nSent: Monday, October 12\n"
            + "To: Me\nSubject: Lunch\n\nLunch at noon?",
        "Sounds good.\n\nFrom: Dana Levi <dana@example.com>\nDate: Monday, October 12, 2026\nTo: Me\n\nLunch at noon?",
    ])
    func quotedHistoryIsTrimmed(_ body: String) {
        #expect(plain(body) == [.text("Sounds good.")])
    }

    @Test(arguments: [
        "Sounds good.\n\n-- \nDana Levi\nProduct, Example Inc.",
        "Sounds good.\n\nSent from my iPhone",
        "Sounds good.\n\nGet Outlook for iOS",
        "Sounds good.\n\nנשלח מה-iPhone שלי",
        "Sounds good.\n--\nDana\n\nOn Mon, Oct 12, 2026, Dana Levi <dana@example.com> wrote:\n> Lunch?",
    ])
    func signaturesAreTrimmed(_ body: String) {
        #expect(plain(body) == [.text("Sounds good.")])
    }

    @Test func inlineAnswersKeepTheLinesTheyAnswerAsQuotes() {
        let body = """
            On Mon, Oct 12, 2026 at 9:10 AM Dana Levi <dana@example.com> wrote:
            > Lunch at noon?
            Yes, noon works.

            > And the slides?
            >> Dana's draft
            Sending them tonight.

            > Thanks
            """
        #expect(
            plain(body) == [
                .quote("Lunch at noon?"), .text("Yes, noon works."), .quote("And the slides?\nDana's draft"),
                .text("Sending them tonight."),
            ])
    }

    @Test func gmailHTMLKeepsTheReplyAboveItsQuoteAndSignature() {
        let markup = """
            <div dir="rtl">שלום, נתראה <b>בצהריים</b>.</div><br><span class="gmail_signature_prefix">-- </span>\
            <div dir="ltr" class="gmail_signature">Avi<br>Example Inc.</div><br>\
            <div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Mon, Oct 12, 2026 at 9:10 AM Dana Levi \
            &lt;dana@example.com&gt; wrote:<br></div><blockquote class="gmail_quote" type="cite">Lunch at noon?\
            </blockquote></div>
            """
        #expect(html(markup) == [.text("שלום, נתראה בצהריים.")])
    }

    @Test func appleMailHTMLInlineRepliesKeepTheirQuotes() {
        let markup = """
            <html><body><div>Inline below.</div><div><br><blockquote type="cite"><div>Lunch at noon?</div>\
            </blockquote>Yes.<br><blockquote type="cite"><div>Slides?</div></blockquote></div></body></html>
            """
        #expect(html(markup) == [.text("Inline below."), .quote("Lunch at noon?"), .text("Yes.")])
    }

    @Test func outlookHTMLStopsAtTheReplyHeader() {
        let markup = """
            <div>Approved.</div><div id="appendonsend"></div><hr><div id="divRplyFwdMsg"><b>From:</b> Dana<br>\
            <b>Sent:</b> Monday</div><div>Can you approve?</div>
            """
        #expect(html(markup) == [.text("Approved.")])
    }

    @Test func aForwardWithoutACommentHasNoNewText() {
        let body = "---------- Forwarded message ---------\nFrom: Dana Levi <dana@example.com>\n\nThe report."
        #expect(plain(body).isEmpty)
    }

    @Test func plainTextWinsOverHTMLWhenBothArePresent() {
        let body = MessageBody(html: "<div>Rich</div>", plain: "Plain\n\n> quoted")
        #expect(ReplyText(body: body).segments == [.text("Plain")])
    }

    @Test func textJoinsTheNewWordsOnly() {
        let reply = ReplyText(body: MessageBody(plain: "> Lunch?\nYes.\n> Slides?\nTonight."))
        #expect(reply.text == "Yes.\nTonight.")
    }
}
