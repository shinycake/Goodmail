import Foundation
import MailCore
import Testing

/// The bold, italics and links HTML gives its words, kept for bubbles that can't show the HTML.
struct StyledTextTests {
    private func styled(_ html: String) -> StyledText { HTMLEntities.styledText(fromHTML: html) }

    @Test func boldAndItalicsKeepTheirWords() {
        let text = styled("<p>See <b>you</b> <i>soon</i>, <strong><em>Dana</em></strong></p>")
        #expect(
            text.runs == [
                .init("See "), .init("you", style: .bold), .init(" "), .init("soon", style: .italic), .init(", "),
                .init("Dana", style: [.bold, .italic]),
            ])
        #expect(text.plain == "See you soon, Dana")
    }

    @Test func headingsAreBold() {
        #expect(
            styled("<h2>Your order</h2><p>Arrives Monday</p>").runs == [
                .init("Your order", style: .bold), .init("\nArrives Monday"),
            ])
    }

    @Test func linksKeepWhereTheyLead() throws {
        let text = styled(#"Read <a href="https://example.com/a?x=1&amp;y=2">the <b>post</b></a>."#)
        let url = try #require(URL(string: "https://example.com/a?x=1&y=2"))
        #expect(
            text.runs == [
                .init("Read "), .init("the ", link: url), .init("post", style: .bold, link: url), .init("."),
            ])
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "cid:logo", ""])
    func onlyWebAndMailLinksLink(_ target: String) {
        #expect(styled(#"<a href="\#(target)">Open</a>"#).runs == [.init("Open")])
    }

    @Test func aBareAddressInTheWordsLinks() throws {
        let url = try #require(URL(string: "https://goodmail.app/beta"))
        #expect(
            StyledText.linking("Join at https://goodmail.app/beta.").runs == [
                .init("Join at "), .init("https://goodmail.app/beta", link: url), .init("."),
            ])
        #expect(
            styled("<p>Join at https://goodmail.app/beta.</p>")
                == StyledText.linking("Join at https://goodmail.app/beta."))
    }

    @Test func anElementLeftOpenEndsWithTheText() {
        #expect(
            styled("<b>Bold<p>Still bold</p>").runs == [
                .init("Bold", style: .bold), .init("\n"), .init("Still bold", style: .bold),
            ])
        #expect(styled("Plain</b> words").runs == [.init("Plain words")])
    }

    @Test func trimmingAndCuttingKeepTheLook() {
        let text = StyledText(runs: [.init("  Hi "), .init("Dana", style: .bold), .init("  \n")])
        #expect(
            text.trimmingCharacters(in: .whitespacesAndNewlines).runs == [.init("Hi "), .init("Dana", style: .bold)])
        #expect(text.prefix(6).runs == [.init("  Hi "), .init("D", style: .bold)])
        #expect(text.split(separator: "\n").map(\.plain) == ["  Hi Dana  ", ""])
    }

    @Test func aBubbleKeepsTheLookOfItsWords() {
        let body = MessageBody(html: "<blockquote>Free?</blockquote><div>Lunch <b>tomorrow</b>?</div>")
        #expect(
            ReplyText(body: body).segments == [
                .quote("Free?"),
                .text(StyledText(runs: [.init("Lunch "), .init("tomorrow", style: .bold), .init("?")])),
            ])
    }

    @Test func survivesTheTrip() throws {
        let text = styled(#"<b>Hi</b> <a href="mailto:dana@example.com">Dana</a>"#)
        #expect(try JSONDecoder().decode(StyledText.self, from: JSONEncoder().encode(text)) == text)
    }
}
