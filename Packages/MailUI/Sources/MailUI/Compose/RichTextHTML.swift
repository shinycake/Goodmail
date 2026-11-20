import Foundation
import MailCore

/// Email-safe HTML for formatted text, and reading it back for a reopened draft. Only tags every mail client keeps
/// (`div`, `ul`, `ol`, `li`, `blockquote`, `b`, `i`, `u`, `s`, `a`, `span`) and inline styles, sizes in `em` of the
/// reader's own and chosen colors as fixed values, the reader's own as none: each paragraph is its own block with `dir`, and a list or quote states
/// the direction of its first line, so bullets and the quote bar sit on the side it starts from even where
/// `dir="auto"` is ignored. A quote's bar is a border on that side, the way Outlook marks its own quotes, since Outlook
/// for Windows draws no other kind.
nonisolated extension RichText {
    var html: String {
        var html = ""
        /// The direction of each quote open around the text, outermost first, and the list open inside them.
        var quotes: [Direction] = []
        var list: Block?
        func closeList() {
            if let open = list { html += open == .numbered ? "</ol>" : "</ul>" }
            list = nil
        }
        for paragraph in paragraphs {
            let level = paragraph.quoteLevel.rawValue
            if list != paragraph.block || quotes.count != level { closeList() }
            while quotes.count > level {
                quotes.removeLast()
                html += "</blockquote>"
            }
            while quotes.count < level {
                let side = paragraph.side
                quotes.append(side)
                html += Self.openQuote(depth: quotes.count, side: side)
            }
            if paragraph.block != .body, list == nil {
                list = paragraph.block
                // No space above and below, as in the editor; the padding on its side keeps room for the bullets.
                html +=
                    "<\(paragraph.block == .numbered ? "ol" : "ul") dir=\"\(paragraph.side.rawValue)\""
                    + " style=\"margin-top:0;margin-bottom:0\">"
            }
            html += Self.html(of: paragraph)
        }
        closeList()
        html += String(repeating: "</blockquote>", count: quotes.count)
        return html
    }

    /// A quote's bar on the side it starts from, in the color of its depth, with the text set off beside it and no
    /// other margin, so it reads as it did in the editor.
    private static func openQuote(depth: Int, side: Direction) -> String {
        let edge = side == .rightToLeft ? "right" : "left"
        return "<blockquote dir=\"\(side.rawValue)\" style=\"margin:0;padding-\(edge):10px;"
            + "border-\(edge):3px solid \(QuoteLevel.barHex(depth: depth))\">"
    }

    private static func html(of paragraph: Paragraph) -> String {
        let tag = paragraph.block == .body ? "div" : "li"
        let content = paragraph.runs.isEmpty ? "<br>" : paragraph.runs.map(html(of:)).joined()
        return "<\(tag) dir=\"\(paragraph.direction.rawValue)\">\(content)</\(tag)>"
    }

    private static func html(of run: Run) -> String {
        var html = HTMLText.escape(run.text)
        for style in Style.allCases where run.styles.contains(style) { html = "<\(style.tag)>\(html)</\(style.tag)>" }
        let css = [
            run.size == .normal ? nil : "font-size:\(run.size.scale)em",
            run.color.hex.map { "color:\($0)" },
        ].compactMap(\.self)
        if !css.isEmpty { html = "<span style=\"\(css.joined(separator: ";"))\">\(html)</span>" }
        if let link = run.link { html = "<a href=\"\(HTMLText.escape(link.absoluteString))\">\(html)</a>" }
        return html
    }

    /// Reads back HTML this extension wrote. A tag it doesn't know is skipped and its text kept.
    init(html: String) {
        var paragraphs: [Paragraph] = []
        /// The quotes and lists open around the text, innermost last: each new paragraph is quoted as deeply as there
        /// are quotes, and is an item of the innermost list.
        var containers: [Container] = []
        var styles: [Style: Int] = [:]
        var links: [URL?] = []
        /// The size and color each open `span` or `font` sets, innermost last; `nil` where it sets none.
        var sizes: [Size?] = []
        var colors: [TextColor?] = []
        func startParagraph(direction: Direction = .auto) {
            let quoteLevel = QuoteLevel(rawValue: containers.count(where: { $0 == .quote }))
            let block =
                containers.last(where: { $0 != .quote }).map { $0 == .numbered ? Block.numbered : .bulleted } ?? .body
            paragraphs.append(Paragraph(block: block, quoteLevel: quoteLevel, direction: direction))
        }
        for match in html.matches(of: /<(\/?)(\w+)([^>]*)>|([^<]+)/) {
            if let text = match.output.4 {
                if paragraphs.isEmpty { startParagraph() }
                paragraphs[paragraphs.count - 1].append(
                    Run(
                        text: Self.unescape(String(text)),
                        styles: Set(Style.allCases.filter { styles[$0, default: 0] > 0 }), link: links.last ?? nil,
                        size: sizes.compactMap(\.self).last ?? .normal,
                        color: colors.compactMap(\.self).last ?? .automatic))
                continue
            }
            guard let name = match.output.2?.lowercased() else { continue }
            let isClosing = match.output.1 == "/"
            let attributes = match.output.3 ?? ""
            switch name {
            case "div", "li", "p":
                guard !isClosing else { break }
                let dir = attributes.firstMatch(of: /dir="(\w+)"/).flatMap { Direction(rawValue: String($0.1)) }
                startParagraph(direction: dir ?? .auto)
            case "ul": containers.toggle(.bulleted, isClosing: isClosing)
            case "ol": containers.toggle(.numbered, isClosing: isClosing)
            case "blockquote": containers.toggle(.quote, isClosing: isClosing)
            case "span", "font":
                if isClosing {
                    _ = sizes.popLast()
                    _ = colors.popLast()
                } else {
                    sizes.append(Size(htmlAttributes: String(attributes)))
                    colors.append(TextColor(htmlAttributes: String(attributes)))
                }
            case "a" where isClosing: _ = links.popLast()
            case "a":
                let href = attributes.firstMatch(of: /href="([^"]*)"/).map { Self.unescape(String($0.1)) }
                links.append(href.flatMap(URL.init(string:)))
            default:
                guard let style = Style(tag: name) else { break }
                styles[style, default: 0] += isClosing ? -1 : 1
            }
        }
        self.init(paragraphs)
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

nonisolated extension RichText.Style {
    /// The tag this style is written as.
    var tag: String {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .underline: "u"
        case .strikethrough: "s"
        }
    }

    /// Also reads the tags other mail apps write for the same styles.
    init?(tag: String) {
        switch tag {
        case "b", "strong": self = .bold
        case "i", "em": self = .italic
        case "u": self = .underline
        case "s", "strike", "del": self = .strikethrough
        default: return nil
        }
    }
}

nonisolated extension RichText.Size {
    /// The size a `span`'s `font-size` in `em`, or an old `font` tag's `size`, comes closest to.
    init?(htmlAttributes attributes: String) {
        let scale: Double
        if let em = attributes.firstMatch(of: /font-size:\s*([\d.]+)em/).flatMap({ Double($0.1) }) {
            scale = em
        } else if let size = attributes.firstMatch(of: /size="?(\d)/).flatMap({ Int($0.1) }) {
            // HTML's seven sizes, 3 being the reader's own.
            scale = [1: 0.6, 2: 0.8, 3: 1, 4: 1.2, 5: 1.5, 6: 2, 7: 3][size] ?? 1
        } else {
            return nil
        }
        self = Self.allCases.min { abs($0.scale - scale) < abs($1.scale - scale) } ?? .normal
    }
}

nonisolated extension RichText.TextColor {
    /// The color of a `span`'s `color` style or a `font` tag's `color`, as a `#rrggbb` value; `nil` for none.
    init?(htmlAttributes attributes: String) {
        guard let hex = attributes.firstMatch(of: /(?:^|[^-\w])color(?::\s*|=")(#[0-9a-fA-F]{6})/)?.1,
            let color = RGBColor(hex: String(hex))
        else { return nil }
        self.init(color)
    }
}

/// An HTML element that holds paragraphs.
nonisolated private enum Container {
    case quote, bulleted, numbered
}

nonisolated extension [Container] {
    /// Opens a `container`, or closes the innermost one.
    fileprivate mutating func toggle(_ container: Container, isClosing: Bool) {
        if isClosing { _ = popLast() } else { append(container) }
    }
}

nonisolated extension RichText.Paragraph {
    /// The side the paragraph starts from, where its quote bar and bullet go.
    var side: RichText.Direction { direction == .auto ? .detected(in: text) : direction }
}

nonisolated extension RichText {
    /// A body to edit again: from its HTML when it has some, otherwise its plain text.
    init(_ body: MessageBody) {
        if let html = body.html { self.init(html: html) } else { self.init(plain: body.plain ?? "") }
    }

    /// The body as it is sent: the HTML, with the plain text alongside.
    var messageBody: MessageBody { MessageBody(html: html, plain: plain) }
}
