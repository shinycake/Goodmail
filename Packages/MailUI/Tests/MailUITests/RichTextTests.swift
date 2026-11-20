import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

private typealias Paragraph = RichText.Paragraph
private typealias Run = RichText.Run
private typealias TextColor = RichText.TextColor

extension RichText.QuoteLevel {
    fileprivate static let one = Self(rawValue: 1)
    fileprivate static let two = Self(rawValue: 2)
}

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
                == #"<ul dir="rtl" style="margin-top:0;margin-bottom:0"><li dir="auto">חלב</li><li dir="auto">eggs</li></ul>"#
                + #"<div dir="auto">Steps:</div>"#
                + #"<ol dir="ltr" style="margin-top:0;margin-bottom:0"><li dir="auto">Mix</li><li dir="rtl">לאפות</li></ol>"#
        )
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
                == #"<ul dir="ltr" style="margin-top:0;margin-bottom:0"><li dir="auto">a</li></ul>"#
                + #"<ol dir="ltr" style="margin-top:0;margin-bottom:0"><li dir="auto">b</li><li dir="auto"><br></li></ol>"#
        )
    }

    /// A quote at `depth` starting from `side`, as sent.
    private func quote(_ depth: Int, _ side: String) -> String {
        let edge = side == "rtl" ? "right" : "left"
        let color = ["#1a73e8", "#2e9e44", "#e8790c"][(depth - 1) % 3]
        return
            #"<blockquote dir="\#(side)" style="margin:0;padding-\#(edge):10px;border-\#(edge):3px solid \#(color)">"#
    }

    @Test func aQuoteHasItsBarOnTheSideItStartsFrom() {
        let english = RichText([
            Paragraph(quoteLevel: .one, runs: [Run(text: "On Monday:")]),
            Paragraph(quoteLevel: .one, runs: [Run(text: "בסדר")]),
        ])
        #expect(
            english.html
                == quote(1, "ltr") + #"<div dir="auto">On Monday:</div><div dir="auto">בסדר</div></blockquote>"#)
        let hebrew = RichText([Paragraph(quoteLevel: .one, runs: [Run(text: "ציטוט")])])
        #expect(hebrew.html == quote(1, "rtl") + #"<div dir="auto">ציטוט</div></blockquote>"#)
        #expect(english.plain == "> On Monday:\n> בסדר")
    }

    @Test func nestedQuotesShareTheOuterQuoteAndListsSitInsideThem() {
        let text = RichText([
            Paragraph(quoteLevel: .one, runs: [Run(text: "You wrote:")]),
            Paragraph(quoteLevel: .two, runs: [Run(text: "Lunch?")]),
            Paragraph(block: .numbered, quoteLevel: .two, runs: [Run(text: "Sushi")]),
            Paragraph(block: .numbered, quoteLevel: .two, runs: [Run(text: "Pizza")]),
            Paragraph(quoteLevel: .one, runs: [Run(text: "Sushi!")]),
            Paragraph(block: .numbered, runs: [Run(text: "Book")]),
        ])
        #expect(
            text.html
                == quote(1, "ltr") + #"<div dir="auto">You wrote:</div>"#
                + quote(2, "ltr") + #"<div dir="auto">Lunch?</div>"#
                + #"<ol dir="ltr" style="margin-top:0;margin-bottom:0"><li dir="auto">Sushi</li><li dir="auto">Pizza</li></ol></blockquote>"#
                + #"<div dir="auto">Sushi!</div></blockquote>"#
                + #"<ol dir="ltr" style="margin-top:0;margin-bottom:0"><li dir="auto">Book</li></ol>"#)
        #expect(text.plain == "> You wrote:\n>> Lunch?\n>> 1. Sushi\n>> 2. Pizza\n> Sushi!\n1. Book")
        #expect(RichText(html: text.html) == text)
    }

    @Test func aListEndsWhereItsQuoteLevelChanges() {
        let text = RichText([
            Paragraph(block: .bulleted, runs: [Run(text: "a")]),
            Paragraph(block: .bulleted, quoteLevel: .one, runs: [Run(text: "b")]),
        ])
        #expect(
            text.html
                == #"<ul dir="ltr" style="margin-top:0;margin-bottom:0"><li dir="auto">a</li></ul>"#
                + quote(1, "ltr")
                + #"<ul dir="ltr" style="margin-top:0;margin-bottom:0"><li dir="auto">b</li></ul></blockquote>"#)
    }

    @Test func gmailsOwnQuotesReadAsNestedLevels() {
        let html =
            #"<div>Sure</div><blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex">"#
            + #"<div>Fine?</div><blockquote class="gmail_quote"><div>Plan</div></blockquote></blockquote>"#
        #expect(RichText(html: html).paragraphs.map(\.quoteLevel) == [.none, .one, .two])
    }

    @Test func anOverriddenDirectionIsWrittenOnItsBlock() {
        let text = RichText([
            Paragraph(direction: .rightToLeft, runs: [Run(text: "OK, נדבר")]),
            Paragraph(quoteLevel: .one, direction: .leftToRight, runs: [Run(text: "שלום")]),
        ])
        #expect(
            text.html
                == #"<div dir="rtl">OK, נדבר</div>"# + quote(1, "ltr") + #"<div dir="ltr">שלום</div></blockquote>"#)
    }

    @Test func everyFormatReadsBackFromItsHTML() {
        let text = RichText([
            Paragraph(direction: .rightToLeft, runs: [Run(text: "שלום "), Run(text: "Dana", styles: [.bold])]),
            Paragraph(),
            Paragraph(block: .bulleted, runs: [Run(text: "a & b", styles: [.italic, .underline])]),
            Paragraph(block: .bulleted, direction: .leftToRight, runs: [Run(text: "c")]),
            Paragraph(block: .numbered, runs: [Run(text: "one")]),
            Paragraph(block: .numbered),
            Paragraph(quoteLevel: .one, runs: [Run(text: "\"quoted\"", link: URL(string: "https://a.example/?x=<1>"))]),
            Paragraph(quoteLevel: .two, direction: .rightToLeft, runs: [Run(text: "x", styles: [.strikethrough])]),
            Paragraph(block: .bulleted, quoteLevel: .one, runs: [Run(text: "y")]),
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

    @Test func sizeAndColorGoInOneSpanAndReadBack() {
        let text = RichText([
            Paragraph(runs: [
                Run(text: "big", styles: [.bold], size: .large, color: TextColor(.red)),
                Run(text: " small", size: .small),
                Run(text: " blue", color: TextColor(.blue)),
            ])
        ])
        #expect(
            text.html
                == ##"<div dir="auto"><span style="font-size:1.4em;color:#e0352b"><b>big</b></span>"##
                + ##"<span style="font-size:0.8em"> small</span><span style="color:#1a73e8"> blue</span></div>"##)
        #expect(text.plain == "big small blue")
        #expect(RichText(html: text.html) == text)
    }

    @Test func oldFontTagsReadAsTheNearestSizeAndTheirColor() {
        let text = RichText(
            html: ##"<div><font size="6" color="#2E9E44">huge</font><font color="#C0FFEE">x</font></div>"##)
        #expect(
            text.paragraphs == [
                Paragraph(runs: [Run(text: "huge", size: .huge, color: TextColor(.green)), Run(text: "x")])
            ],
            "a color too pale to read on white is the reader's own")
    }

    @Test func anyPickedColorIsSentAsItReadsAndReadsBack() throws {
        let picked = TextColor(RGBColor(red: 0xFF, green: 0xEE, blue: 0x00))
        let text = RichText([Paragraph(runs: [Run(text: "note", color: picked)])])
        let hex = try #require(picked.hex)
        #expect(text.html == ##"<div dir="auto"><span style="color:\##(hex)">note</span></div>"##)
        #expect(RichText(html: text.html) == text)
    }

    @Test func theReadersOwnColorIsSentAsNoColor() {
        let text = RichText([Paragraph(runs: [Run(text: "hi")])])
        #expect(!text.html.contains("color"))
    }

    @Test func aQuotedMessagesBlackStaysTheReadersOwnWhenADraftReopens() {
        let text = RichText(html: ##"<div><span style="color:#000000">quoted</span></div>"##)
        #expect(text.paragraphs == [Paragraph(runs: [Run(text: "quoted")])])
    }

    @Test func aBackgroundColorIsNotTheTextColor() {
        let text = RichText(html: ##"<div><span style="background-color:#e0352b">x</span></div>"##)
        #expect(text.paragraphs == [Paragraph(runs: [Run(text: "x")])])
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
            Paragraph(quoteLevel: .one, runs: [Run(text: "quoted", styles: [.strikethrough])]),
            Paragraph(block: .bulleted, quoteLevel: .two, runs: [Run(text: "deeper")]),
            Paragraph(),
        ])
        let shown = text.attributedString(font: font)
        #expect(shown.string == "Hi there\nפריט\none\nquoted\ndeeper\n")
        #expect(RichText(shown) == text)
    }

    @Test func listsAreSystemTextListsAndQuotesAreMarked() throws {
        let shown = RichText([
            Paragraph(block: .bulleted, runs: [Run(text: "a")]),
            Paragraph(block: .numbered, runs: [Run(text: "b")]),
            Paragraph(quoteLevel: .one, runs: [Run(text: "c")]),
            Paragraph(block: .bulleted, quoteLevel: .two, runs: [Run(text: "d")]),
        ])
        .attributedString(font: font)
        func style(at location: Int) throws -> NSParagraphStyle {
            try #require(shown.attribute(.paragraphStyle, at: location) as? NSParagraphStyle)
        }
        #expect(try style(at: 0).textLists.map(\.markerFormat) == [.disc])
        #expect(try style(at: 2).textLists.map(\.isOrdered) == [true])
        #expect(try style(at: 4).textLists.isEmpty)
        #expect(shown.attribute(.blockQuote, at: 4) as? Int == 1)
        #expect(shown.attribute(.blockQuote, at: 6) as? Int == 2)
        #expect(shown.attribute(.blockQuote, at: 2) == nil)
        // Each level moves the text in by one more step, and a list inside a quote further still.
        #expect(try style(at: 6).headIndent > 2 * style(at: 4).headIndent)
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

    @Test func sizeAndColorApplyToTheSelectionAndKeepItsStyles() throws {
        let text = editor(RichText([Paragraph(runs: [Run(text: "one "), Run(text: "two", styles: [.bold])])]))
        let all = NSRange(location: 0, length: 7)
        _ = apply(.size(.huge), to: text, selection: all)
        _ = apply(.color(TextColor(.purple)), to: text, selection: NSRange(location: 4, length: 3))
        #expect(
            RichText(text).paragraphs == [
                Paragraph(runs: [
                    Run(text: "one ", size: .huge),
                    Run(text: "two", styles: [.bold], size: .huge, color: TextColor(.purple)),
                ])
            ])
        #expect(Formatting(text: text, selection: all, typingAttributes: [:]).size == .huge)
        #expect(Formatting(text: text, selection: all, typingAttributes: [:]).color == nil, "mixed")
        _ = apply(.size(.normal), to: text, selection: all)
        _ = apply(.color(.automatic), to: text, selection: all)
        #expect(
            RichText(text).paragraphs == [Paragraph(runs: [Run(text: "one "), Run(text: "two", styles: [.bold])])])
        let font = try #require(text.attribute(.font, at: 0) as? UIFont)
        #expect(font.pointSize == 17)
    }

    @Test func textInTheReadersColorDrawsInTheLabelColorSoItShowsInDarkMode() {
        let text = editor(RichText([Paragraph(runs: [Run(text: "בדיקה"), Run(text: " red", color: TextColor(.red))])]))
        #expect(text.attribute(.foregroundColor, at: 0) as? UIColor == .label)
        let red = UIColor(TextInk(TextColor.Preset.red.rgb).color)
        #expect(text.attribute(.foregroundColor, at: 6) as? UIColor == red)
        #expect(RichText.plainAttributes(font: font)[.foregroundColor] as? UIColor == .label)
    }

    @Test func aMovedCaretTypesInTheSizeAndColorOfTheTextItContinues() {
        let red = TextColor(.red)
        let text = editor(
            RichText([Paragraph(runs: [Run(text: "big red", size: .large, color: red), Run(text: " plain")])]))
        // What UIKit hands over: the character's font and color, without the keys the text reads back from.
        let uikit: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: red.color]
        let typing = RichText.typingRun(in: text, at: 7, typingAttributes: uikit)
        #expect(TextColor(typing) == red)
        #expect(RichText.Size(typing) == .large)
        let after = RichText.typingRun(in: text, at: 13, typingAttributes: typing)
        #expect(TextColor(after) == .automatic)
        #expect(RichText.Size(after) == .normal)
        #expect(after[.foregroundColor] as? UIColor == .label)
        let start = RichText.typingRun(in: text, at: 0, typingAttributes: [.font: font])
        #expect(TextColor(start) == red, "at the very start, the text after it")
        let lines = editor(
            RichText([Paragraph(runs: [Run(text: "red", color: red)]), Paragraph(runs: [Run(text: "plain")])]))
        let nextLine = RichText.typingRun(
            in: lines, at: 4, typingAttributes: [.font: font, .foregroundColor: red.color])
        #expect(TextColor(nextLine) == .automatic, "a line's start continues its own text, not the line above")
        lines.append(NSAttributedString(string: "\n", attributes: [.textColor: TextColor(.blue).hex ?? ""]))
        let emptyLine = RichText.typingRun(in: lines, at: lines.length, typingAttributes: [.font: font])
        #expect(TextColor(emptyLine) == TextColor(.blue), "a new empty line continues the color Return was typed in")
    }

    @Test func pastedColorsSettleToTheColorsThatAreSent() {
        let text = editor(RichText(plain: "hi "))
        text.append(NSAttributedString(string: "pasted", attributes: [.font: font, .foregroundColor: UIColor.black]))
        text.settleColors(in: NSRange(location: 3, length: 6))
        #expect(text.attribute(.foregroundColor, at: 4) as? UIColor == .label)
        #expect(RichText(text).paragraphs == [Paragraph(runs: [Run(text: "hi pasted")])])
    }

    @Test func aSizeAtTheCaretAppliesToWhatIsTypedNext() {
        let text = editor(RichText(plain: "hi"))
        let edit = apply(.size(.large), to: text, selection: NSRange(location: 2, length: 0))
        #expect(RichText.Size(edit.typingAttributes) == .large)
        #expect((edit.typingAttributes[.font] as? UIFont)?.pointSize ?? 0 > 17)
    }

    @Test func aBlockAppliesToEveryTouchedParagraphAndTogglesBack() {
        let text = editor(
            RichText([
                Paragraph(direction: .rightToLeft, runs: [Run(text: "אחת", styles: [.bold])]),
                Paragraph(runs: [Run(text: "two")]),
                Paragraph(runs: [Run(text: "three")]),
            ]))
        let selection = NSRange(location: 1, length: 4)
        _ = apply(.quote(.toggle), to: text, selection: selection)
        #expect(RichText(text).paragraphs.map(\.quoteLevel) == [.one, .one, .none])
        #expect(RichText(text).paragraphs[0].direction == .rightToLeft)
        #expect(RichText(text).paragraphs[0].runs == [Run(text: "אחת", styles: [.bold])])
        #expect(Formatting(text: text, selection: selection, typingAttributes: [:]).quoteLevel == .one)
        _ = apply(.block(.numbered), to: text, selection: selection)
        #expect(RichText(text).paragraphs.map(\.block) == [.numbered, .numbered, .body])
        #expect(RichText(text).paragraphs.map(\.quoteLevel) == [.one, .one, .none])
        _ = apply(.block(.numbered), to: text, selection: selection)
        #expect(RichText(text).paragraphs.map(\.block) == [.body, .body, .body])
        _ = apply(.quote(.toggle), to: text, selection: selection)
        #expect(RichText(text).paragraphs.map(\.quoteLevel) == [.none, .none, .none])
    }

    @Test func quoteLevelsStepInAndOutWithinTheirLimits() {
        let text = editor(
            RichText([
                Paragraph(quoteLevel: .one, runs: [Run(text: "a")]),
                Paragraph(runs: [Run(text: "b")]),
            ]))
        let both = NSRange(location: 0, length: 3)
        _ = apply(.quote(.increase), to: text, selection: both)
        #expect(RichText(text).paragraphs.map(\.quoteLevel) == [.two, .one])
        _ = apply(.quote(.decrease), to: text, selection: both)
        #expect(RichText(text).paragraphs.map(\.quoteLevel) == [.one, .none])
        // Toggling goes by the first paragraph: quoted, so every touched paragraph leaves its quotes.
        _ = apply(.quote(.toggle), to: text, selection: both)
        #expect(RichText(text).paragraphs.map(\.quoteLevel) == [.none, .none])
        for _ in 0..<6 { _ = apply(.quote(.increase), to: text, selection: both) }
        #expect(RichText(text).paragraphs.map(\.quoteLevel) == [.deepest, .deepest])
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
                Paragraph(quoteLevel: .two), Paragraph(runs: [Run(text: "end")]),
            ]))
        #expect(
            FormattingCommand.onReturn(in: text, selection: NSRange(location: 2, length: 0), typingAttributes: [:])
                == nil)
        #expect(
            FormattingCommand.onReturn(in: text, selection: NSRange(location: 5, length: 0), typingAttributes: [:])
                == .block(.bulleted))
        #expect(
            FormattingCommand.onReturn(in: text, selection: NSRange(location: 6, length: 0), typingAttributes: [:])
                == .quote(.decrease))
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

/// How the editor joins quoted paragraphs into bars.
struct QuoteBarLayoutTests {
    private typealias Line = QuoteBarLayout.Paragraph

    @Test func anOuterBarRunsPastADeeperQuoteAndStopsAtUnquotedText() {
        let bars = QuoteBarLayout.bars(for: [
            Line(level: 1, isRightToLeft: false, top: 0, bottom: 20),
            Line(level: 2, isRightToLeft: false, top: 20, bottom: 40),
            Line(level: 1, isRightToLeft: true, top: 40, bottom: 60),
            Line(level: 0, isRightToLeft: false, top: 60, bottom: 80),
            Line(level: 1, isRightToLeft: true, top: 80, bottom: 100),
        ])
        #expect(
            bars == [
                QuoteBar(depth: 2, isOnRight: false, top: 20, bottom: 40),
                QuoteBar(depth: 1, isOnRight: false, top: 0, bottom: 60),
                QuoteBar(depth: 1, isOnRight: true, top: 80, bottom: 100),
            ])
    }
}

/// How typing keeps each paragraph laid out as one.
@MainActor
struct ParagraphLayoutTests {
    let font = UIFont.systemFont(ofSize: 17)

    private func editor(_ text: RichText) -> NSMutableAttributedString {
        NSMutableAttributedString(attributedString: text.attributedString(font: font))
    }

    /// Types `typed` at `location` the way the composer does: with the typing layout, then settled.
    private func type(
        _ typed: String, at location: Int, in text: NSMutableAttributedString, typing: [NSAttributedString.Key: Any]
    ) {
        let range = NSRange(location: location, length: 0)
        let attributes = FormattingCommand.typingLayout(in: text, at: range, typingAttributes: typing)
        text.replaceCharacters(in: range, with: NSAttributedString(string: typed, attributes: attributes))
        text.settleLayout(around: NSRange(location: location, length: (typed as NSString).length), font: font)
    }

    @Test func aQuotedParagraphReadsAndIndentsTheWayItsTextDoes() throws {
        let shown = editor(RichText([Paragraph(quoteLevel: .one, runs: [Run(text: "שלום")])]))
        let style = try #require(shown.attribute(.paragraphStyle, at: 0) as? NSParagraphStyle)
        #expect(style.baseWritingDirection == .rightToLeft)
        #expect(style.headIndent > 0)
        #expect(RichText(shown).paragraphs[0].direction == .auto)
    }

    @Test func returnInAQuoteContinuesItEvenWhenTypingLostTheQuote() {
        let text = editor(RichText([Paragraph(quoteLevel: .one, runs: [Run(text: "quoted")])]))
        type("\n", at: 6, in: text, typing: text.attributes(at: 5))
        // Typing the next line starts from the line break's attributes, which UIKit may hand back without the quote.
        var typing = text.attributes(at: 6)
        typing[.blockQuote] = nil
        type("more", at: 7, in: text, typing: typing)
        #expect(RichText(text).paragraphs.map(\.quoteLevel) == [.one, .one])
    }

    @Test func typingIntoAParagraphTakesItsLayout() {
        let text = editor(
            RichText([
                Paragraph(runs: [Run(text: "a")]),
                Paragraph(block: .bulleted, quoteLevel: .two, runs: [Run(text: "b")]),
            ]))
        type("x", at: 2, in: text, typing: [.font: font])
        #expect(RichText(text).paragraphs[1] == Paragraph(block: .bulleted, quoteLevel: .two, runs: [Run(text: "xb")]))
    }

    @Test func theFirstLetterTypedTurnsAnEmptyQuotedLineToItsDirection() throws {
        let text = editor(
            RichText([
                Paragraph(runs: [Run(text: "Hi")]), Paragraph(quoteLevel: .one), Paragraph(runs: [Run(text: "Bye")]),
            ]))
        // UIKit types from the attributes of the character before the caret, the previous line's break.
        type("ש", at: 3, in: text, typing: text.attributes(at: 2))
        let style = try #require(text.attribute(.paragraphStyle, at: 3) as? NSParagraphStyle)
        #expect(style.baseWritingDirection == .rightToLeft)
        #expect(RichText(text).paragraphs[1].quoteLevel == .one)
    }
}
