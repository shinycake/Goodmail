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
        in body: MessageBody, palette: MessagePalette, appearance: ForcedAppearance
    ) async throws -> [String: [String: String]] {
        let view = await MessageScriptPage.load(body, palette: palette, appearance: appearance).view
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
        let marks = try await marks(in: notice, palette: .painted, appearance: .dark)
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
        let marks = try await marks(in: body, palette: .sendersOwn, appearance: .dark)
        #expect(marks["paper"]?["panel"] == MessageDarkPass.sheet)
        #expect(marks["ink"]?["text"] == nil, "their white text reads on the turned panel")
    }

    @Test(arguments: [MessagePalette.painted, .sendersOwn])
    func lightLeavesTheSendersColors(palette: MessagePalette) async throws {
        let marks = try await marks(in: notice, palette: palette, appearance: .light)
        #expect(marks.values.allSatisfy { $0.isEmpty })
    }

    @Test func plainMailIsLeftToTheAdaptivePass() async throws {
        let body = MessageBody(html: #"<div id="black" style="color: #000; border: 1px solid #eee">Hi</div>"#)
        let marks = try await marks(in: body, palette: .adaptive, appearance: .dark)
        #expect(marks.values.allSatisfy { $0.isEmpty })
    }

    /// The computed background and text color of each element by id, once the pass has run in dark.
    private func computed(_ body: MessageBody, palette: MessagePalette) async throws -> [String: [String]] {
        let view = await MessageScriptPage.load(body, palette: palette, appearance: .dark).view
        let script = """
            (() => Object.fromEntries([...document.querySelectorAll('[id]')].map((el) => {
              const style = getComputedStyle(el);
              return [el.id, [style.backgroundColor, style.color]];
            })))()
            """
        return try #require(try await view.evaluateJavaScript(script) as? [String: [String]])
    }

    @Test func theSendersImportantStylesheetRulesStillTurn() async throws {
        let body = MessageBody(
            html: """
                <style>.panel { background-color: #ffffff !important; }</style>\
                <table class="panel" id="panel"><tr><td id="text" style="color: #0d1b4c">Hi</td></tr></table>
                """)
        let shown = try await computed(body, palette: .painted)
        #expect(shown["panel"]?.first == MessageDarkPass.sheet)
        let text = try channels(shown["text"]?.last)
        #expect(text.allSatisfy { $0 > 120 }, "the navy text reads on the turned panel")
    }

    @Test func aPanelHeldLightInlineKeepsItsOwnDarkText() async throws {
        let body = MessageBody(
            html: """
                <div id="panel" style="background-color: #fff !important">\
                <span id="text" style="color: #0d1b4c">Hi</span></div>
                """)
        let shown = try await computed(body, palette: .painted)
        #expect(shown["panel"]?.first == "rgb(255, 255, 255)")
        #expect(shown["text"]?.last == "rgb(13, 27, 76)", "no pale text on the white the sender insisted on")
    }

    @Test func textOnALightColorTheSenderKeptTurnsDark() async throws {
        let body = MessageBody(html: #"<div id="button" style="background: #ff9900">Buy</div>"#)
        let shown = try await computed(body, palette: .painted)
        #expect(shown["button"]?.first == "rgb(255, 153, 0)", "a brand orange stays")
        let text = try channels(shown["button"]?.last)
        #expect(text.allSatisfy { $0 < 60 }, "its default white text in dark turns dark to read")
    }
}
