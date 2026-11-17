import Foundation

/// Gmail snippets are HTML-escaped text (`&#39;`, `&amp;`, `&quot;`…). This decodes the entities they use.
public enum HTMLEntities {
    private static let named: [Substring: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    public static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = text[...]
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let afterAmpersand = rest[rest.index(after: ampersand)...]
            if let semicolon = afterAmpersand.prefix(10).firstIndex(of: ";"),
                let character = character(for: afterAmpersand[..<semicolon])
            {
                result.append(character)
                rest = afterAmpersand[afterAmpersand.index(after: semicolon)...]
            } else {
                result.append("&")
                rest = afterAmpersand
            }
        }
        return result + rest
    }

    private static func character(for entity: Substring) -> Character? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            return UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(Character.init)
        }
        if entity.hasPrefix("#") {
            return UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map(Character.init)
        }
        return named[entity]
    }
}

extension HTMLEntities {
    /// The words and line breaks of HTML, such as a Gmail signature for the plain-text composer or a message body
    /// for the search index. Styles, scripts, the head and comments are left out: they are not words of the mail.
    ///
    /// The HTML may be cut short, as the start of a message that IMAP fetches for a snippet is. A comment, style,
    /// script or title still open at the end runs to the end, and so does a tag cut in half. A head left open is kept,
    /// since a whole page may leave out `</head>`; what is in it is mostly the elements above.
    public static func plainText(fromHTML html: String) -> String {
        styledText(fromHTML: html).plain
    }

    /// The words of HTML as `plainText(fromHTML:)` reads them, keeping what bold, italics, headings and links give
    /// them, for a bubble to show where no web view can.
    public static func styledText(fromHTML html: String) -> StyledText {
        guard html.contains("<") else { return lines(of: StyledText(decode(html))) }
        // Each element is spelled out: a back-reference to its name would miss `<Style>…</STYLE>`, as it matches case.
        let visible = html.replacing(
            /(?is)<!--.*?(?:-->|\z)|<style\b[^>]*>.*?(?:<\/style\s*>|\z)|<script\b[^>]*>.*?(?:<\/script\s*>|\z)/,
            with: ""
        )
        .replacing(/(?is)<title\b[^>]*>.*?(?:<\/title\s*>|\z)|<head\b[^>]*>.*?<\/head\s*>/, with: "")
        .replacing(/<[a-zA-Z\/!][^>]*\z/, with: "")
        // Each block starts a line; a `<br>` that only holds a block open, as in `<div><br></div>`, adds none.
        // A table's cells stay apart on their row. Tags stay after their break, since a heading's sets its look.
        let broken = listed(visible).replacing(/(?i)<br\s*\/?>\s*(?=<\/(div|p)>)/, with: "")
            .replacing(/(?i)<br\s*\/?>/, with: "\n")
            .replacing(/(?i)<(div|p|tr|h\d)\b[^>]*>/) { "\n" + $0.output.0 }
            .replacing(/(?i)<(td|th)\b[^>]*>/, with: " ")
        return lines(of: InlineMarkup.read(broken))
    }

    private enum List {
        case bulleted
        /// Holds the number of the item last started.
        case numbered(Int)
    }

    /// Each list item starts a line with a bullet, or with its number in an ordered list, nested lists included.
    private static func listed(_ html: String) -> String {
        guard html.contains(/(?i)<li\b/) else { return html }
        var result = ""
        var lists: [List] = []
        var rest = html[...]
        while let tag = rest.firstMatch(of: /(?i)<(\/?)(ol|ul|li)\b[^>]*>/) {
            result += rest[..<tag.range.lowerBound]
            rest = rest[tag.range.upperBound...]
            let name = tag.output.2.lowercased()
            if !tag.output.1.isEmpty {
                if name != "li", !lists.isEmpty { lists.removeLast() }
            } else if name == "ol" {
                lists.append(.numbered(0))
            } else if name == "ul" {
                lists.append(.bulleted)
            } else if case .numbered(let number) = lists.last {
                lists[lists.count - 1] = .numbered(number + 1)
                result += "\n\(number + 1). "
            } else {
                result += "\n• "
            }
        }
        return result + rest
    }

    /// The text with each line trimmed, and the blank lines around it dropped.
    private static func lines(of text: StyledText) -> StyledText {
        StyledText.joined(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }, separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
