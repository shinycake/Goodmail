import Foundation

/// Gmail snippets are HTML-escaped text (`&#39;`, `&amp;`, `&quot;`…). This decodes the entities they use.
enum HTMLEntities {
    private static let named: [Substring: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    static func decode(_ text: String) -> String {
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
    /// The words and line breaks of an HTML fragment, such as a Gmail signature, for the plain-text composer.
    static func plainText(fromHTML html: String) -> String {
        // Each block starts a line; a `<br>` that only holds a block open, as in `<div><br></div>`, adds none.
        let broken = html.replacing(/(?i)<br\s*\/?>\s*(?=<\/(div|p)>)/, with: "")
            .replacing(/(?i)<br\s*\/?>|<(div|p|li|tr|h\d)\b[^>]*>/, with: "\n")
        let text = decode(broken.replacing(/<[^>]*>/, with: ""))
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
