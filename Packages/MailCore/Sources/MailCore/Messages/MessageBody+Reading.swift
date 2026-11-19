import Foundation

extension MessageBody {
    /// The part of a body a reader reads, and how: as lines of plain text, or as HTML to take the words from.
    public enum Reading: Equatable, Sendable {
        case plain(String)
        case html(String)
        /// Neither part holds anything.
        case empty
    }

    /// The plain part when it holds words, since every client writes it and it keeps quotes as `>` lines; otherwise
    /// the HTML. A plain part that is really markup, as some senders write it and as a message without a
    /// Content-Type header reads, is never read as lines: its words come from the HTML.
    public var reading: Reading {
        if let plain = Self.filled(plain), !Self.isMarkup(plain) { return .plain(plain) }
        return markup.map(Reading.html) ?? .empty
    }

    /// The body's HTML to show: the HTML part, or else a plain part that is really markup.
    public var markup: String? {
        if let html = Self.filled(html) { return html }
        return Self.filled(plain).flatMap { Self.isMarkup($0) ? $0 : nil }
    }

    /// The body as plain text: the plain part, or else the HTML's words.
    public var text: String {
        switch reading {
        case .plain(let plain): plain
        case .html(let html): HTMLEntities.plainText(fromHTML: html)
        case .empty: ""
        }
    }

    /// The whole body as words, with the bold, italics and links it gives them, for a screen that can't show HTML,
    /// as the watch's. What a newsletter hides is left out: an element styled `display: none`, such as the preview
    /// line written for inboxes, and the invisible characters that pad it. Blank lines in a row read as one, since a
    /// laid-out message spaces its blocks with many.
    public var styledText: StyledText {
        let words: StyledText =
            switch reading {
            case .plain(let plain): StyledText.linking(plain.replacingOccurrences(of: "\r\n", with: "\n"))
            case .html(let html): HTMLEntities.styledText(fromHTML: Self.withoutHidden(html))
            case .empty: StyledText()
            }
        return Self.tidied(words)
    }

    /// `words` without invisible characters, each line trimmed, and blank lines in a row read as one.
    static func tidied(_ words: StyledText) -> StyledText {
        var lines: [StyledText] = []
        for line in words.mapRuns(withoutInvisibles).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(trimmed)
        }
        if lines.last?.isEmpty == true { lines.removeLast() }
        return StyledText.joined(lines, separator: "\n")
    }

    /// The HTML without the elements styled `display: none`. One that holds another of its own kind ends at the inner
    /// one's close, leaving the rest of it to show, which is no worse than showing all of it.
    private static func withoutHidden(_ html: String) -> String {
        html.replacing(/(?is)<(div|span|p|td|table)\b[^>]*display\s*:\s*none[^>]*>.*?<\/\1\s*>/, with: "")
    }

    /// Characters that take no space, which newsletters repeat after the preview line so inboxes show no more of it.
    /// A joiner that builds an emoji stays.
    private static func withoutInvisibles(_ text: String) -> String {
        let invisibles: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{FEFF}", "\u{034F}", "\u{00AD}"]
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { !invisibles.contains($0) }))
    }

    private static func filled(_ part: String?) -> String? {
        guard let part, part.contains(where: { !$0.isWhitespace }) else { return nil }
        return part
    }

    /// A page's own tags, or a few elements, closed or empty, that only markup writes. Words that mention one tag,
    /// as "use a <div> there", aren't markup.
    static func isMarkup(_ text: String) -> Bool {
        guard text.contains("<") else { return false }
        if text.contains(/(?i)<!doctype\s+html|<html\b|<body\b/) { return true }
        var found = 0
        var rest = text[...]
        let element =
            /(?i)<\/?(p|div|span|br|table|tbody|tr|td|th|a|b|i|u|strong|em|font|li|ul|ol|h[1-6]|img|blockquote|center)\b[^<>]*>/
        while let tag = rest.firstMatch(of: element) {
            found += 1
            if found == 3 { return true }
            rest = rest[tag.range.upperBound...]
        }
        return false
    }
}

extension HTMLEntities {
    /// A snippet's words on one line. A provider that makes snippets from a plain part that is really markup, as
    /// Gmail does, hands over the tags too.
    public static func words(ofSnippet snippet: String) -> String {
        guard MessageBody.isMarkup(snippet) else { return snippet }
        return plainText(fromHTML: snippet).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
