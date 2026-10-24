import MailCore
import UIKit

/// Turns what the writer typed into email-safe HTML and plain text. Every paragraph is its own `dir="auto"` block,
/// so each reads in its own direction in any mail client; bold, italic, underline, strikethrough and links carry over.
nonisolated enum RichTextSerializer {
    static func body(from text: NSAttributedString) -> MessageBody {
        MessageBody(html: html(from: text), plain: text.string)
    }

    static func html(from text: NSAttributedString) -> String {
        let string = text.string as NSString
        var html = ""
        var location = 0
        while location <= string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            var content = NSRange(location: paragraph.location, length: paragraph.length)
            // Leave out the line break that ends the paragraph.
            while content.length > 0,
                CharacterSet.newlines.contains(UnicodeScalar(string.character(at: NSMaxRange(content) - 1)) ?? " ")
            {
                content.length -= 1
            }
            html +=
                content.length == 0
                ? "<div dir=\"auto\"><br></div>" : "<div dir=\"auto\">\(runs(text, in: content))</div>"
            location = NSMaxRange(paragraph)
            if location >= string.length {
                // A final line break starts one more, empty line.
                if content.length < paragraph.length { html += "<div dir=\"auto\"><br></div>" }
                break
            }
        }
        return html
    }

    /// Reads back HTML this serializer wrote, so a reopened draft keeps its text and styling. Falls back to the
    /// plain text when there is no HTML.
    static func attributedText(from body: MessageBody, font: UIFont) -> NSAttributedString {
        guard let html = body.html else {
            return NSAttributedString(string: body.plain ?? "", attributes: [.font: font])
        }
        let text = NSMutableAttributedString()
        var bold = 0
        var italic = 0
        var underline = 0
        var strikethrough = 0
        var links: [URL?] = []
        var paragraphs = 0
        for match in html.matches(of: /<(\/?)(\w+)([^>]*)>|([^<]+)/) {
            if let run = match.output.4 {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if bold > 0 { traits.insert(.traitBold) }
                if italic > 0 { traits.insert(.traitItalic) }
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) }
                        ?? font
                ]
                if underline > 0 { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if strikethrough > 0 { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let link = links.last ?? nil { attributes[.link] = link }
                text.append(NSAttributedString(string: unescape(String(run)), attributes: attributes))
                continue
            }
            let isClosing = match.output.1 == "/"
            let step = isClosing ? -1 : 1
            switch match.output.2?.lowercased() {
            case "div":
                guard !isClosing else { break }
                if paragraphs > 0 { text.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
                paragraphs += 1
            case "b": bold += step
            case "i": italic += step
            case "u": underline += step
            case "s": strikethrough += step
            case "a":
                if isClosing {
                    _ = links.popLast()
                } else {
                    let href = match.output.3.flatMap { $0.firstMatch(of: /href="([^"]*)"/)?.output.1 }
                    links.append(href.flatMap { URL(string: unescape(String($0))) })
                }
            default: break
            }
        }
        return text
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func runs(_ text: NSAttributedString, in range: NSRange) -> String {
        var html = ""
        text.enumerateAttributes(in: range) { attributes, run, _ in
            var piece = HTMLText.escape((text.string as NSString).substring(with: run))
            let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.traitBold) { piece = "<b>\(piece)</b>" }
            if traits.contains(.traitItalic) { piece = "<i>\(piece)</i>" }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 { piece = "<u>\(piece)</u>" }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { piece = "<s>\(piece)</s>" }
            if let link = attributes[.link] as? URL ?? (attributes[.link] as? String).flatMap(URL.init(string:)) {
                piece = "<a href=\"\(HTMLText.escape(link.absoluteString))\">\(piece)</a>"
            }
            html += piece
        }
        return html
    }
}
