import Foundation

/// A search as typed, in Gmail's syntax: words, and operators such as `from:dana` or `subject:"lunch plans"`.
/// The provider takes the text as it is; the store and the search field read the terms.
public struct SearchQuery: Hashable, Sendable {
    public struct Term: Hashable, Sendable {
        /// The operator, lowercased, such as `from` or `is`; nil for a plain word.
        public var name: String?
        public var value: String

        public init(_ name: String? = nil, _ value: String) {
            self.name = name
            self.value = value
        }

        public static func word(_ text: String) -> Term { Term(nil, text) }
        public static let unread = Term("is", "unread")
        public static let starred = Term("is", "starred")
        public static let hasAttachment = Term("has", "attachment")
        public static func from(_ address: String) -> Term { Term("from", address) }
        public static func subject(_ text: String) -> Term { Term("subject", text) }

        /// The term as Gmail reads it, quoting a value with spaces.
        public var text: String {
            let value = value.contains(where: \.isWhitespace) ? "\"\(value.replacing("\"", with: ""))\"" : value
            return name.map { "\($0):\(value)" } ?? value
        }
    }

    public var terms: [Term]

    public init(terms: [Term]) {
        self.terms = terms
    }

    public init(_ text: String) {
        var terms: [Term] = []
        var rest = Substring(text)
        while let start = rest.firstIndex(where: { !$0.isWhitespace }) {
            rest = rest[start...]
            var name: String?
            if let colon = rest.firstIndex(of: ":"), colon > rest.startIndex,
                rest[..<colon].allSatisfy(\.isLetter), rest.index(after: colon) < rest.endIndex,
                !rest[rest.index(after: colon)].isWhitespace
            {
                name = rest[..<colon].lowercased()
                rest = rest[rest.index(after: colon)...]
            }
            let value: Substring
            if rest.first == "\"" {
                let inside = rest.dropFirst()
                let close = inside.firstIndex(of: "\"") ?? inside.endIndex
                value = inside[..<close]
                rest = close < inside.endIndex ? inside[inside.index(after: close)...] : inside[close...]
            } else {
                let end = rest.firstIndex(where: \.isWhitespace) ?? rest.endIndex
                value = rest[..<end]
                rest = rest[end...]
            }
            if !value.allSatisfy(\.isWhitespace) { terms.append(Term(name, String(value))) }
        }
        self.terms = terms
    }

    public var text: String { terms.map(\.text).joined(separator: " ") }
    public var isEmpty: Bool { terms.isEmpty }
}
