public import Foundation

/// Words with the emphasis and links their mail gave them: what a bubble shows where a web view can't, as on the
/// watch. Runs next to each other never share a look, so two styled texts with the same words and looks are equal.
public struct StyledText: Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public struct Style: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let bold = Style(rawValue: 1 << 0)
        public static let italic = Style(rawValue: 1 << 1)
    }

    public struct Run: Hashable, Codable, Sendable {
        public var text: String
        public var style: Style
        /// Where the words lead: a web page or an address, never a script.
        public var link: URL?

        public init(_ text: String, style: Style = [], link: URL? = nil) {
            self.text = text
            self.style = style
            self.link = link
        }

        fileprivate func looks(like other: Run) -> Bool { style == other.style && link == other.link }
    }

    public private(set) var runs: [Run] = []

    public init() {}

    /// Words without a look of their own.
    public init(_ text: String) {
        append(text)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(runs: [Run]) {
        for run in runs { append(run) }
    }

    /// The words alone.
    public var plain: String { runs.map(\.text).joined() }
    public var description: String { plain }
    public var isEmpty: Bool { runs.isEmpty }

    public mutating func append(_ text: String, style: Style = [], link: URL? = nil) {
        append(Run(text, style: style, link: link))
    }

    public mutating func append(_ run: Run) {
        guard !run.text.isEmpty else { return }
        if let last = runs.last, last.looks(like: run) {
            runs[runs.count - 1].text += run.text
        } else {
            runs.append(run)
        }
    }

    public mutating func append(_ other: StyledText) {
        for run in other.runs { append(run) }
    }

    public static func + (lhs: StyledText, rhs: StyledText) -> StyledText {
        var joined = lhs
        joined.append(rhs)
        return joined
    }

    public static func joined(_ texts: [StyledText], separator: String) -> StyledText {
        var joined = StyledText()
        for (index, text) in texts.enumerated() {
            if index > 0 { joined.append(separator) }
            joined.append(text)
        }
        return joined
    }

    // MARK: - Characters

    /// The characters that pass `isIncluded`, each keeping its look.
    public func filter(_ isIncluded: (Character) -> Bool) -> StyledText {
        mapRuns { String($0.filter(isIncluded)) }
    }

    /// Each run's words changed by `transform`, keeping their look.
    public func mapRuns(_ transform: (String) -> String) -> StyledText {
        StyledText(runs: runs.map { Run(transform($0.text), style: $0.style, link: $0.link) })
    }

    /// The first `count` characters.
    public func prefix(_ count: Int) -> StyledText {
        var left = count
        var cut = StyledText()
        for run in runs where left > 0 {
            cut.append(Run(String(run.text.prefix(left)), style: run.style, link: run.link))
            left -= run.text.count
        }
        return cut
    }

    /// Splits at each `separator`, keeping empty pieces, as `split(separator:omittingEmptySubsequences: false)` does.
    public func split(separator: Character) -> [StyledText] {
        var pieces = [StyledText()]
        for run in runs {
            for (index, piece) in run.text.split(separator: separator, omittingEmptySubsequences: false).enumerated() {
                if index > 0 { pieces.append(StyledText()) }
                pieces[pieces.count - 1].append(Run(String(piece), style: run.style, link: run.link))
            }
        }
        return pieces
    }

    /// Without the characters of `set` at either end.
    public func trimmingCharacters(in set: CharacterSet) -> StyledText {
        let isTrimmed = { (character: Character) in
            character.unicodeScalars.allSatisfy(set.contains)
        }
        let characters = plain
        let leading = characters.prefix(while: isTrimmed).count
        let kept = characters.count - leading - characters.reversed().prefix(while: isTrimmed).count
        return dropFirst(leading).prefix(max(0, kept))
    }

    private func dropFirst(_ count: Int) -> StyledText {
        var left = count
        var rest = StyledText()
        for run in runs {
            let dropped = min(left, run.text.count)
            left -= dropped
            rest.append(Run(String(run.text.dropFirst(dropped)), style: run.style, link: run.link))
        }
        return rest
    }
}

extension StyledText {
    /// Plain words with each web address in them made a link, as mail clients show a plain-text message.
    public static func linking(_ text: String) -> StyledText {
        var linked = StyledText()
        var rest = text[...]
        while let match = rest.firstMatch(of: /(?i)\bhttps?:\/\/[^\s<>"]+/) {
            // Punctuation that ends a sentence isn't part of the address.
            var address = match.output[...]
            while let last = address.last, ".,;:!?)]}'".contains(last) { address.removeLast() }
            linked.append(String(rest[..<match.range.lowerBound]))
            linked.append(String(address), link: URL(string: String(address)))
            rest = rest[address.endIndex...]
        }
        linked.append(String(rest))
        return linked
    }

    /// A link's target when it is a web page or an address to write to. Anything else, such as `javascript:` or a
    /// file, is no link at all.
    public static func link(_ target: String) -> URL? {
        guard let url = URL(string: target.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme)
        else { return nil }
        return url
    }
}
