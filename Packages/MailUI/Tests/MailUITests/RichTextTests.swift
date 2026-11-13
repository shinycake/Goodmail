import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

private typealias Paragraph = RichText.Paragraph
private typealias Run = RichText.Run

/// Golden HTML for each format: what is sent must render the same in Gmail web, Apple Mail and Outlook, and read back
/// into the same text when the draft is reopened.
struct RichTextHTMLTests {
    @Test func mixedHebrewAndEnglishParagraphsAreEachTheirOwnAutoBlock() {
        let text = RichText([
            Paragraph(runs: [Run(text: "Hi <Dana>,")]),
            Paragraph(),
            Paragraph(runs: [Run(text: "שלום "), Run(text: "עולם", styles: [.bold]), Run(text: " and English")]),
        ])
        #expect(
            text.html
                == #"<div dir="auto">Hi &lt;Dana&gt;,</div><div dir="auto"><br></div>"#
                + #"<div dir="auto">שלום <b>עולם</b> and English</div>"#)
        #expect(text.plain == "Hi <Dana>,\n\nשלום עולם and English")
    }

    @Test func nestedStylesAndLinksWrapInAFixedOrder() {
        let link = URL(string: "https://example.com/?a=1&b=2")!
        let text = RichText([
            Paragraph(runs: [
                Run(text: "all", styles: Set(RichText.Style.allCases), link: link),
                Run(text: " plain "),
                Run(text: "struck", styles: [.strikethrough, .italic]),
            ])
        ])
        #expect(
            text.html
                == #"<div dir="auto"><a href="https://example.com/?a=1&amp;b=2"><s><u><i><b>all</b></i></u></s></a>"#
                + #" plain <s><i>struck</i></s></div>"#)
    }

    @Test func listsTakeTheDirectionOfTheirFirstLine() {
        let text = RichText([
            Paragraph(block: .bulleted, runs: [Run(text: "חלב")]),
            Paragraph(block: .bulleted, runs: [Run(text: "eggs")]),
            Paragraph(runs: [Run(text: "Steps:")]),
            Paragraph(block: .numbered, runs: [Run(text: "Mix")]),
            Paragraph(block: .numbered, direction: .rightToLeft, runs: [Run(text: "לאפות")]),
        ])
        #expect(
            text.html
                == #"<ul dir="rtl"><li dir="auto">חלב</li><li dir="auto">eggs</li></ul>"#
                + #"<div dir="auto">Steps:</div>"#
                + #"<ol dir="ltr"><li dir="auto">Mix</li><li dir="rtl">לאפות</li></ol>"#)
        #expect(text.plain == "• חלב\n• eggs\nSteps:\n1. Mix\n2. לאפות")
    }

    @Test func neighbouringListsOfDifferentKindsStaySeparate() {
        let text = RichText([
            Paragraph(block: .bulleted, runs: [Run(text: "a")]),
            Paragraph(block: .numbered, runs: [Run(text: "b")]),
            Paragraph(block: .numbered),
        ])
        #expect(
            text.html
                == #"<ul dir="ltr"><li dir="auto">a</li></ul>"#
                + #"<ol dir="ltr"><li dir="auto">b</li><li dir="auto"><br></li></ol>"#)
    }

    @Test func aQuoteHasItsBarOnTheSideItStartsFrom() {
        let english = RichText([
            Paragraph(block: .quote, runs: [Run(text: "On Monday:")]),
            Paragraph(block: .quote, runs: [Run(text: "בסדר")]),
        ])
        #expect(
            english.html
                == #"<blockquote dir="ltr" style="margin:0 0 0 0.8ex;border-left:1px solid #ccc;padding-left:1ex">"#
                + #"<div dir="auto">On Monday:</div><div dir="auto">בסדר</div></blockquote>"#)
        let hebrew = RichText([Paragraph(block: .quote, runs: [Run(text: "ציטוט")])])
        #expect(
            hebrew.html
                == #"<blockquote dir="rtl" style="margin:0 0.8ex 0 0;border-right:1px solid #ccc;padding-right:1ex">"#
                + #"<div dir="auto">ציטוט</div></blockquote>"#)
        #expect(english.plain == "> On Monday:\n> בסדר")
    }

    @Test func anOverriddenDirectionIsWrittenOnItsBlock() {
        let text = RichText([
            Paragraph(direction: .rightToLeft, runs: [Run(text: "OK, נדבר")]),
            Paragraph(block: .quote, direction: .leftToRight, runs: [Run(text: "שלום")]),
        ])
        #expect(
            text.html
                == #"<div dir="rtl">OK, נדבר</div>"#
                + #"<blockquote dir="ltr" style="margin:0 0 0 0.8ex;border-left:1px solid #ccc;padding-left:1ex">"#
                + #"<div dir="ltr">שלום</div></blockquote>"#)
    }

    @Test func everyFormatReadsBackFromItsHTML() {
        let text = RichText([
            Paragraph(direction: .rightToLeft, runs: [Run(text: "שלום "), Run(text: "Dana", styles: [.bold])]),
            Paragraph(),
            Paragraph(block: .bulleted, runs: [Run(text: "a & b", styles: [.italic, .underline])]),
            Paragraph(block: .bulleted, direction: .leftToRight, runs: [Run(text: "c")]),
            Paragraph(block: .numbered, runs: [Run(text: "one")]),
            Paragraph(block: .numbered),
            Paragraph(block: .quote, runs: [Run(text: "\"quoted\"", link: URL(string: "https://a.example/?x=<1>"))]),
            Paragraph(block: .quote, direction: .rightToLeft, runs: [Run(text: "x", styles: [.strikethrough])]),
            Paragraph(runs: [Run(text: "end")]),
        ])
        #expect(RichText(html: text.html) == text)
        #expect(RichText(text.messageBody) == text)
    }

    @Test func otherMailAppsTagsReadAsTheSameStyles() {
        let text = RichText(html: "<div><strong>b</strong><em>i</em><del>s</del><span>plain</span></div>")
        #expect(
            text.paragraphs == [
                Paragraph(runs: [
                    Run(text: "b", styles: [.bold]), Run(text: "i", styles: [.italic]),
                    Run(text: "s", styles: [.strikethrough]), Run(text: "plain"),
                ])
            ])
    }

    @Test func aBodyWithoutHTMLReadsAsPlainLines() {
        let text = RichText(MessageBody(html: nil, plain: "\n\n-- \nDana"))
        #expect(text.paragraphs.map(\.text) == ["", "", "-- ", "Dana"])
        #expect(text.plain == "\n\n-- \nDana")
    }

    @Test func emptyAndTrailingLinesSurvive() {
        #expect(RichText(NSAttributedString(string: "")).html == #"<div dir="auto"><br></div>"#)
        #expect(
            RichText(NSAttributedString(string: "a\n")).html == #"<div dir="auto">a</div><div dir="auto"><br></div>"#)
    }

    @Test func directionIsDetectedFromTheFirstLetter() {
        #expect(RichText.Direction.detected(in: "12, שלום world") == .rightToLeft)
        #expect(RichText.Direction.detected(in: "— hello שלום") == .leftToRight)
        #expect(RichText.Direction.detected(in: "مرحبا") == .rightToLeft)
        #expect(RichText.Direction.detected(in: "123") == .leftToRight)
    }
}

/// The editor's text: what `UITextView` shows, converted to and from the same model.
@MainActor
struct RichTextAttributesTests {
    let font = UIFont.systemFont(ofSize: 17)

    @Test func theEditorsTextReadsBackAsTheSameModel() {
        let text = RichText([
            Paragraph(runs: [Run(text: "Hi "), Run(text: "there", styles: [.bold, .italic])]),
            Paragraph(block: .bulleted, direction: .rightToLeft, runs: [Run(text: "פריט", styles: [.underline])]),
            Paragraph(block: .numbered, runs: [Run(text: "one", link: URL(string: "https://example.com"))]),
            Paragraph(block: .quote, runs: [Run(text: "quoted", styles: [.strikethrough])]),
            Paragraph(),
        ])
        let shown = text.attributedString(font: font)
        #expect(shown.string == "Hi there\nפריט\none\nquoted\n")
        #expect(RichText(shown) == text)
    }

    @Test func listsAreSystemTextListsAndQuotesAreMarked() throws {
        let shown = RichText([
            Paragraph(block: .bulleted, runs: [Run(text: "a")]),
            Paragraph(block: .numbered, runs: [Run(text: "b")]),
            Paragraph(block: .quote, runs: [Run(text: "c")]),
        ])
        .attributedString(font: font)
        func style(at location: Int) throws -> NSParagraphStyle {
            try #require(shown.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
        }
        #expect(try style(at: 0).textLists.map(\.markerFormat) == [.disc])
        #expect(try style(at: 2).textLists.map(\.isOrdered) == [true])
        #expect(try style(at: 4).textLists.isEmpty)
        #expect(shown.attribute(.blockQuote, at: 4, effectiveRange: nil) != nil)
        #expect(shown.attribute(.blockQuote, at: 2, effectiveRange: nil) == nil)
    }

    @Test func aParagraphPastedWithASystemHyphenListIsBulleted() {
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: .hyphen, options: 0)]
        let pasted = NSAttributedString(string: "item", attributes: [.font: font, .paragraphStyle: style])
        #expect(RichText(pasted).paragraphs.map(\.block) == [.bulleted])
    }
}

/// What the formatting controls show for a selection, and the edit each one makes.
@MainActor
struct FormattingTests {
    let font = UIFont.systemFont(ofSize: 17)

    private func editor(_ text: RichText) -> NSMutableAttributedString {
        NSMutableAttributedString(attributedString: text.attributedString(font: font))
    }

    private func apply(
        _ command: FormattingCommand, to text: NSMutableAttributedString, selection: NSRange,
        typing: [NSAttributedString.Key: Any]? = nil
    ) -> FormattingCommand.Edit {
        let edit = command.edit(
            text: text, selection: selection, typingAttributes: typing ?? [.font: font], font: font)
        text.replaceCharacters(in: edit.range, with: edit.replacement)
        return edit
    }

    @Test func aStyleTurnsOnForTheSelectionThenOffWhenAllOfItHasIt() {
        let text = editor(RichText([Paragraph(runs: [Run(text: "one "), Run(text: "two", styles: [.bold])])]))
        let all = NSRange(location: 0, length: 7)
        #expect(Formatting(text: text, selection: all, typingAttributes: [:]).styles == [])
        _ = apply(.toggle(.bold), to: text, selection: all)
        #expect(RichText(text).paragraphs == [Paragraph(runs: [Run(text: "one two", styles: [.bold])])])
        #expect(Formatting(text: text, selection: all, typingAttributes: [:]).styles == [.bold])
        _ = apply(.toggle(.bold), to: text, selection: NSRange(location: 4, length: 3))
        #expect(RichText(text).paragraphs == [Paragraph(runs: [Run(text: "one ", styles: [.bold]), Run(text: "two")])])
    }

    @Test func aStyleAtTheCaretAppliesToWhatIsTypedNext() {
        let text = editor(RichText(plain: "hi"))
        let edit = apply(.toggle(.italic), to: text, selection: NSRange(location: 2, length: 0))
        #expect(edit.range.length == 0 && edit.replacement.length == 0)
        #expect(Set(attributes: edit.typingAttributes) == [.italic])
        let off = apply(
            .toggle(.italic), to: text, selection: NSRange(location: 2, length: 0), typing: edit.typingAttributes)
        #expect(Set(attributes: off.typingAttributes) == [])
    }

    @Test func aBlockAppliesToEveryTouchedParagraphAndTogglesBack() {
        let text = editor(
            RichText([
                Paragraph(direction: .rightToLeft, runs: [Run(text: "אחת", styles: [.bold])]),
                Paragraph(runs: [Run(text: "two")]),
                Paragraph(runs: [Run(text: "three")]),
            ]))
        let selection = NSRange(location: 1, length: 4)
        _ = apply(.block(.quote), to: text, selection: selection)
        #expect(RichText(text).paragraphs.map(\.block) == [.quote, .quote, .body])
        #expect(RichText(text).paragraphs[0].direction == .rightToLeft)
        #expect(RichText(text).paragraphs[0].runs == [Run(text: "אחת", styles: [.bold])])
        #expect(Formatting(text: text, selection: selection, typingAttributes: [:]).block == .quote)
        _ = apply(.block(.numbered), to: text, selection: selection)
        #expect(RichText(text).paragraphs.map(\.block) == [.numbered, .numbered, .body])
        _ = apply(.block(.numbered), to: text, selection: selection)
        #expect(RichText(text).paragraphs.map(\.block) == [.body, .body, .body])
    }

    @Test func theCaretsEmptyLastLineTakesTheBlockThroughTyping() {
        let text = editor(RichText(plain: "a\n"))
        let edit = apply(.block(.bulleted), to: text, selection: NSRange(location: 2, length: 0))
        #expect(RichText(text).paragraphs.map(\.block) == [.body, .body])
        #expect(RichText.Block(edit.typingAttributes) == .bulleted)
    }

    @Test func directionChangesKeepTheBlock() {
        let text = editor(RichText([Paragraph(block: .bulleted, runs: [Run(text: "OK")])]))
        _ = apply(.direction(.rightToLeft), to: text, selection: NSRange(location: 1, length: 0))
        #expect(
            RichText(text).paragraphs == [Paragraph(block: .bulleted, direction: .rightToLeft, runs: [Run(text: "OK")])]
        )
        _ = apply(.direction(.auto), to: text, selection: NSRange(location: 1, length: 0))
        #expect(RichText(text).paragraphs[0].direction == .auto)
    }

    @Test func aLinkCoversTheSelectionOrIsTypedOutAtTheCaret() throws {
        let url = try #require(URL(string: "https://example.com"))
        let text = editor(RichText(plain: "see docs"))
        _ = apply(.link(url), to: text, selection: NSRange(location: 4, length: 4))
        #expect(RichText(text).paragraphs[0].runs == [Run(text: "see "), Run(text: "docs", link: url)])
        #expect(Formatting(text: text, selection: NSRange(location: 6, length: 0), typingAttributes: [:]).link == url)
        #expect(Formatting(text: text, selection: NSRange(location: 4, length: 0), typingAttributes: [:]).link == nil)

        _ = apply(.link(nil), to: text, selection: NSRange(location: 6, length: 0))
        #expect(RichText(text).paragraphs[0].runs == [Run(text: "see docs")])

        let typed = apply(.link(url), to: text, selection: NSRange(location: 0, length: 0))
        #expect(typed.selection == NSRange(location: 19, length: 0))
        #expect(
            RichText(text).paragraphs[0].runs == [Run(text: "https://example.com", link: url), Run(text: "see docs")])
    }

    @Test func returnOnAnEmptyItemEndsTheListOrQuote() {
        let text = editor(
            RichText([
                Paragraph(block: .bulleted, runs: [Run(text: "milk")]), Paragraph(block: .bulleted),
                Paragraph(block: .quote), Paragraph(runs: [Run(text: "end")]),
            ]))
        #expect(
            FormattingCommand.onReturn(in: text, selection: NSRange(location: 2, length: 0), typingAttributes: [:])
                == nil)
        #expect(
            FormattingCommand.onReturn(in: text, selection: NSRange(location: 5, length: 0), typingAttributes: [:])
                == .block(.bulleted))
        #expect(
            FormattingCommand.onReturn(in: text, selection: NSRange(location: 6, length: 0), typingAttributes: [:])
                == .block(.quote))
        let plain = editor(RichText(plain: "a\n"))
        #expect(
            FormattingCommand.onReturn(in: plain, selection: NSRange(location: 2, length: 0), typingAttributes: [:])
                == nil)
    }

    @Test func aTypedAddressBecomesALink() {
        #expect(FormattingCommand.linkURL(from: " example.com/a ") == URL(string: "https://example.com/a"))
        #expect(FormattingCommand.linkURL(from: "http://x.org") == URL(string: "http://x.org"))
        #expect(FormattingCommand.linkURL(from: "dana@example.com") == URL(string: "mailto:dana@example.com"))
        #expect(FormattingCommand.linkURL(from: "not a link") == nil)
        #expect(FormattingCommand.linkURL(from: "word") == nil)
        #expect(FormattingCommand.linkURL(from: "javascript:alert(1)") == nil, "only web and mail links")
        #expect(FormattingCommand.linkURL(from: "file:///etc/hosts") == nil)
        #expect(FormattingCommand.linkURL(from: "MAILTO:dana@example.com") == URL(string: "MAILTO:dana@example.com"))
    }
}
