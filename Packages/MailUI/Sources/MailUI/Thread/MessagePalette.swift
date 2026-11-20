import Foundation
import MailCore

/// How a message body's colors meet the reader's light or dark appearance. Each body has exactly one, decided once
/// from its markup, and the document's stylesheet, the script's contrast pass and the web view's frame all follow it.
nonisolated enum MessagePalette: String, CaseIterable, Sendable {
    /// The sender painted no backgrounds, as in plain text and most personal mail. The text follows the reader's
    /// appearance, and any color the sender gave text that is too faint on the card is lightened or darkened, keeping
    /// its hue, in that appearance.
    case adaptive
    /// The sender styled a dark appearance themselves, with `prefers-color-scheme` or `color-scheme`. Theirs decides,
    /// and the script's dark pass catches what it missed, such as a white panel their dark rules never reached.
    case sendersOwn
    /// The sender painted backgrounds for a light page, as newsletters do. In light it is a white sheet with every
    /// color the sender set. In dark the script's dark pass turns it over as Gmail does: light backgrounds darken,
    /// text that would then be too faint lightens, and the sender's dark brand colors stay.
    case painted

    static func of(_ body: MessageBody) -> MessagePalette {
        guard let html = body.html, !html.isEmpty else { return .adaptive }
        if html.range(of: darkSupport, options: [.regularExpression, .caseInsensitive]) != nil { return .sendersOwn }
        return paintedBackgrounds(in: html).contains { !isBlank($0) } ? .painted : .adaptive
    }

    /// The colors and images the markup paints behind content: `bgcolor` and `background` attributes, and the
    /// values of `background`, `background-color` and `background-image` declarations.
    static func paintedBackgrounds(in html: String) -> [String] {
        let regex =
            #/
            (?i) \b bgcolor \s* = \s* ["']? ([^"'\s>]+)
            | \b background \s* = \s* ["']? ([^"'\s>]+)
            | background (?:-color|-image)? \s* : \s* ([^;"'}]+)
            /#
        return html.matches(of: regex).compactMap { match in
            (match.output.1 ?? match.output.2 ?? match.output.3).map(String.init)
        }
    }

    /// A white or see-through background paints nothing a reader would miss on the card: most personal mail sets
    /// one out of habit, and the script clears it in dark appearance.
    static func isBlank(_ background: String) -> Bool {
        let value = background.lowercased().replacingOccurrences(of: "!important", with: "")
            .filter { !$0.isWhitespace }
        return blankBackgrounds.contains(value)
    }

    private static let blankBackgrounds: Set<String> = [
        "white", "#fff", "#ffffff", "rgb(255,255,255)", "rgba(255,255,255,1)", "transparent", "none", "inherit",
        "initial", "unset", "rgba(0,0,0,0)", "window",
    ]

    /// `prefers-color-scheme: dark` in the sender's styles, or a `color-scheme` that names dark.
    private static let darkSupport =
        #"prefers-color-scheme\s*:\s*dark|(supported-)?color-scheme["']?\s*(:|content\s*=)[^;>}]*dark"#

    /// The palette's rules, after our base styles and before the sender's.
    var style: String {
        switch self {
        case .adaptive:
            // The script marks text whose own color is too faint on the card in an appearance, with a replacement of
            // the same hue, and white backgrounds; these rules apply them in that appearance only.
            """
            <style>\
            :root { color-scheme: light dark; }\
            @media (prefers-color-scheme: dark) {\
            [data-goodmail-faint-on-dark] { color: var(--goodmail-on-dark) !important; }\
            [data-goodmail-white] { background-color: transparent !important; }\
            }\
            @media (prefers-color-scheme: light) {\
            [data-goodmail-faint-on-light] { color: var(--goodmail-on-light) !important; }\
            }\
            </style>
            """
        case .sendersOwn:
            "<style>:root { color-scheme: light dark; }</style>\(Self.darkPassStyle)"
        case .painted:
            """
            <style>:root { color-scheme: light dark; background-color: light-dark(#fff, \(ReaderColors.css(ReaderColors.darkSheet))); }\
            body { padding: 12px; }</style>\(Self.darkPassStyle)
            """
        }
    }

    /// Applies the marks the script's dark pass sets (`message-dark.js`), in dark appearance only, so the sun button
    /// shows the sender's own colors again without a reload. In a layer, so these `!important` rules beat the sender's
    /// own `!important` stylesheet rules, as responsive templates' are, whatever their specificity.
    private static let darkPassStyle = """
        <style>@layer goodmail-dark { @media (prefers-color-scheme: dark) {\
        [data-goodmail-dark-paper] { background-color: var(--goodmail-dark-paper) !important; }\
        [data-goodmail-dark-plate] { background-color: var(--goodmail-dark-plate) !important; }\
        [data-goodmail-dark-ink] { color: var(--goodmail-dark-ink) !important; }\
        [data-goodmail-dark-border] { border-top-color: var(--goodmail-dark-border-top) !important; \
        border-right-color: var(--goodmail-dark-border-right) !important; \
        border-bottom-color: var(--goodmail-dark-border-bottom) !important; \
        border-left-color: var(--goodmail-dark-border-left) !important; }\
        } }</style>
        """
}
