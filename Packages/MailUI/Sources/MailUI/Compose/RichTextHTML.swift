import Foundation
import MailCore

/// Email-safe HTML for formatted text, and reading it back for a reopened draft. Only tags every mail client keeps
/// (`div`, `ul`, `ol`, `li`, `blockquote`, `b`, `i`, `u`, `s`, `a`) and inline styles: each paragraph is its own block
/// with `dir`, and a list or quote states the direction of its first line, so bullets and the quote bar sit on the
/// side it starts from even where `dir="auto"` is ignored.
nonisolated extension RichText {
    var html: String {
        groups.map { group in
            let first = group[group.startIndex]
            let side = first.direction == .auto ? Direction.detected(in: first.text) : first.direction
            let lines = group.map(Self.html(of:)).joined()
            switch first.block {
            case .body: return lines
            case .bulleted: return "<ul dir=\"\(side.rawValue)\">\(lines)</ul>"
            case .numbered: return "<ol dir=\"\(side.rawValue)\">\(lines)</ol>"
            case .quote:
                let edge = side == .rightToLeft ? "right" : "left"
                let margin = side == .rightToLeft ? "0 0.8ex 0 0" : "0 0 0 0.8ex"
                return "<blockquote dir=\"\(side.rawValue)\" style=\"margin:\(margin);"
                    + "border-\(edge):1px solid #ccc;padding-\(edge):1ex\">\(lines)</blockquote>"
            }
        }
        .joined()
    }

    private static func html(of paragraph: Paragraph) -> String {
        let tag = paragraph.block == .bulleted || paragraph.block == .numbered ? "li" : "div"
        let content = paragraph.runs.isEmpty ? "<br>" : paragraph.runs.map(html(of:)).joined()
        return "<\(tag) dir=\"\(paragraph.direction.rawValue)\">\(content)</\(tag)>"
    }

    private static func html(of run: Run) -> String {
        var html = HTMLText.escape(run.text)
        for style in Style.allCases where run.styles.contains(style) { html = "<\(style.tag)>\(html)</\(style.tag)>" }
        if let link = run.link { html = "<a href=\"\(HTMLText.escape(link.absoluteString))\">\(html)</a>" }
        return html
    }

    /// Reads back HTML this extension wrote. A tag it doesn't know is skipped and its text kept.
    init(html: String) {
        var paragraphs: [Paragraph] = []
        /// The containers open around the text, innermost last: the block each new paragraph gets.
        var containers: [Block] = []
        var styles: [Style: Int] = [:]
        var links: [URL?] = []
        func startParagraph(direction: Direction = .auto) {
            paragraphs.append(Paragraph(block: containers.last ?? .body, direction: direction))
        }
        for match in html.matches(of: /<(\/?)(\w+)([^>]*)>|([^<]+)/) {
            if let text = match.output.4 {
                if paragraphs.isEmpty { startParagraph() }
                paragraphs[paragraphs.count - 1].append(
                    Run(
                        text: Self.unescape(String(text)),
                        styles: Set(Style.allCases.filter { styles[$0, default: 0] > 0 }), link: links.last ?? nil))
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

nonisolated extension [RichText.Block] {
    /// Opens a container of `block`, or closes the innermost one.
    fileprivate mutating func toggle(_ block: RichText.Block, isClosing: Bool) {
        if isClosing { _ = popLast() } else { append(block) }
    }
}

nonisolated extension RichText {
    /// A body to edit again: from its HTML when it has some, otherwise its plain text.
    init(_ body: MessageBody) {
        if let html = body.html { self.init(html: html) } else { self.init(plain: body.plain ?? "") }
    }

    /// The body as it is sent: the HTML, with the plain text alongside.
    var messageBody: MessageBody { MessageBody(html: html, plain: plain) }
}
