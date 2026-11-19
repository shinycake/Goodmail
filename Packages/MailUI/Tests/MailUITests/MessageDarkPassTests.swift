import MailCore
import Testing
import UIKit
import WebKit

@testable import MailUI

/// Runs the message script's dark pass on real WebKit: a body that painted its own light colors turns over in dark,
/// keeps its dark brand colors, and is left alone in light.
@MainActor
struct MessageDarkPassTests {
    /// The marks the pass set, by element id: what kind ("paper", "ink" or "border") and the color it set.
    private func marks(
        in body: MessageBody, palette: MessagePalette, style: UIUserInterfaceStyle
    ) async throws -> [String: [String: String]] {
        let view = await MessageScriptPage.load(body, palette: palette, style: style).view
        let script = """
            (() => Object.fromEntries(['paper', 'ink', 'border'].map((kind) => [kind, Object.fromEntries(
              [...document.querySelectorAll('[data-goodmail-dark-' + kind + ']')].filter((el) => el.id)
                .map((el) => [el.id, el.style.getPropertyValue(
                  kind === 'border' ? '--goodmail-dark-border-bottom' : '--goodmail-dark-' + kind)]))])))()
            """
        return try #require(try await view.evaluateJavaScript(script) as? [String: [String: String]])
    }

    private func channels(_ color: String?) throws -> [Int] {
        let values = try #require(color).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        try #require(values.count == 3)
        return values
    }

    /// A delivery notice: a navy banner, a white panel of navy text with a link, a pastel note and a pale divider.
    private let notice = MessageBody(
        html: """
            <div id="banner" style="background: #0d1b4c; color: #fff">Fetch</div>\
            <table id="panel" bgcolor="#ffffff"><tr><td id="text" style="color: #0d1b4c">Your package arrives \
            <a id="link" href="https://example.com" style="color: #1a0dab">here</a></td></tr></table>\
            <div id="note" style="background-color: #e8f0fe; border-bottom: 1px solid #eeeeee">Note</div>\
            <div id="hero" style="background-image: url(cid:hero); color: #0d1b4c">On a photo</div>
            """)

    @Test func aPaintedBodyTurnsOverInDark() async throws {
        let marks = try await marks(in: notice, palette: .painted, style: .dark)
        let paper = try #require(marks["paper"])
        let ink = try #require(marks["ink"])

        #expect(paper["banner"] == nil, "the brand's navy stays")
        #expect(ink["banner"] == nil, "white on navy already reads")
        #expect(paper["panel"] == MessageDarkPass.sheet, "white becomes the sheet")
        let note = try channels(paper["note"])
        #expect(note[2] > note[0] && note.allSatisfy { $0 < 100 }, "a pastel becomes a deep tint of its hue")
        let divider = try channels(marks["border"]?["note"])
        #expect(divider.allSatisfy { $0 < 100 }, "a pale divider darkens")
        let text = try channels(ink["text"])
        #expect(text.allSatisfy { $0 > 120 } && text[2] >= text[0], "navy text turns pale, keeping its hue")
        let link = try channels(ink["link"])
        #expect(link[2] > link[0] && link[2] > link[1], "a link stays blue")
        #expect(ink["hero"] == nil, "text over an image stays as the sender set it")
    }

    @Test func theSendersOwnDarkStylesGetTheirMissedPanelTurned() async throws {
        let body = MessageBody(
            html: """
                <style>@media (prefers-color-scheme: dark) { .ink { color: #fff !important; } }</style>\
                <table id="panel" bgcolor="#ffffff"><tr><td id="text" class="ink">Hi Idan</td></tr></table>
                """)
        let marks = try await marks(in: body, palette: .sendersOwn, style: .dark)
        #expect(marks["paper"]?["panel"] == MessageDarkPass.sheet)
        #expect(marks["ink"]?["text"] == nil, "their white text reads on the turned panel")
    }

    @Test(arguments: [MessagePalette.painted, .sendersOwn])
    func lightLeavesTheSendersColors(palette: MessagePalette) async throws {
        let marks = try await marks(in: notice, palette: palette, style: .light)
        #expect(marks.values.allSatisfy { $0.isEmpty })
    }

    @Test func plainMailIsLeftToTheAdaptivePass() async throws {
        let body = MessageBody(html: #"<div id="black" style="color: #000; border: 1px solid #eee">Hi</div>"#)
        let marks = try await marks(in: body, palette: .adaptive, style: .dark)
        #expect(marks.values.allSatisfy { $0.isEmpty })
    }
}
