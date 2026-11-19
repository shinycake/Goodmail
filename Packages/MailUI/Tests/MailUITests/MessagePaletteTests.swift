import MailCore
import Testing
import WebKit

@testable import MailUI

struct MessagePaletteTests {
    @Test(arguments: [
        (MessageBody(plain: "Hello"), MessagePalette.adaptive),
        (MessageBody(html: #"<div style="color: rgb(0, 0, 0)">Sent from Goodmail</div>"#), .adaptive),
        (MessageBody(html: #"<div style="background-color: #FFFFFF; color: #333">Hi</div>"#), .adaptive),
        (MessageBody(html: #"<table bgcolor="white"><tr><td>Hi</td></tr></table>"#), .adaptive),
        (MessageBody(html: ##"<table bgcolor="#f4f4f4"><tr><td>Sale</td></tr></table>"##), .painted),
        (MessageBody(html: #"<td style="background:#1a73e8;color:#fff">Open</td>"#), .painted),
        (MessageBody(html: #"<div style="background-image: url(cid:hero)">Hi</div>"#), .painted),
        (
            MessageBody(
                html:
                    ##"<style>@media (prefers-color-scheme: dark) { body { color: #eee } }</style><body bgcolor="#fff7e6">"##
            ), .sendersOwn
        ),
        (
            MessageBody(html: ##"<meta name="color-scheme" content="light dark"><td bgcolor="#eee">Hi</td>"##),
            .sendersOwn
        ),
        (MessageBody(html: #"<style>:root { color-scheme: light only }</style><p>Hi</p>"#), .adaptive),
    ])
    func paletteFollowsWhatTheSenderPainted(body: MessageBody, palette: MessagePalette) {
        #expect(MessagePalette.of(body) == palette)
    }

    @Test(arguments: MessagePalette.allCases)
    func theDocumentNamesItsPaletteForTheScript(palette: MessagePalette) {
        let html = MessageDocument.html(
            for: MessageBody(html: "<p>Hi</p>"), palette: palette, allowsRemoteContent: true)
        #expect(html.contains(#"<meta name="goodmail-palette" content="\#(palette.rawValue)">"#))
        #expect(html.contains(palette.style))
    }
}

/// Runs the message script on real WebKit, where it marks the text it recolors.
@MainActor
struct MessageContrastTests {
    /// Each mark the script set, by element id, with the replacement color it set alongside.
    private func marks(in body: MessageBody, palette: MessagePalette) async throws -> [String: [String: String]] {
        let view = await MessageScriptPage.load(body, palette: palette).view
        let script = """
            (() => Object.fromEntries(['dark', 'light'].map((name) => [name, Object.fromEntries(
              [...document.querySelectorAll('[data-goodmail-faint-on-' + name + ']')].filter((el) => el.id)
                .map((el) => [el.id, el.style.getPropertyValue('--goodmail-on-' + name)]))])
              .concat([['white', Object.fromEntries([...document.querySelectorAll('[data-goodmail-white]')]
                .map((el) => [el.id, ''])) ]])))()
            """
        return try #require(try await view.evaluateJavaScript(script) as? [String: [String: String]])
    }

    @Test func textTooFaintOnTheCardIsRecoloredForThatAppearance() async throws {
        let body = MessageBody(
            html: """
                <div id="black" style="color: #000">Sent from Goodmail</div>\
                <div id="pale" style="color: #f0f0f0">Pale</div>\
                <div id="red" style="color: #c5221f">Dark red</div>\
                <div id="orange" style="color: #e8710a">Readable on dark</div>\
                <div id="hidden" style="color: rgba(0, 0, 0, 0)">Preheader</div>\
                <div id="sheet" style="background-color: #fff">On white</div>
                """)
        let marks = try await marks(in: body, palette: .adaptive)
        let dark = try #require(marks["dark"])
        let light = try #require(marks["light"])
        #expect(dark["black"] == "CanvasText")
        #expect(light["pale"] == "CanvasText")
        let red = try #require(dark["red"], "lightened, keeping its hue")
        let channels = red.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        #expect(channels.count == 3 && channels[0] > channels[1] && channels[0] > channels[2])
        #expect(light["red"] == nil)
        #expect(dark["orange"] == nil)
        #expect(light["orange"] != nil)
        #expect(dark["hidden"] == nil && light["hidden"] == nil, "transparent text stays hidden")
        #expect(marks["white"]?.keys.sorted() == ["sheet"])
    }

    @Test(arguments: [MessagePalette.sendersOwn, .painted])
    func otherPalettesKeepTheSendersColors(palette: MessagePalette) async throws {
        let body = MessageBody(html: #"<div id="black" style="color: #000">Hi</div>"#)
        let marks = try await marks(in: body, palette: palette)
        #expect(marks.values.allSatisfy { $0.isEmpty })
    }
}
