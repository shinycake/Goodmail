import Foundation

/// The words a message adds to its conversation: its body without the quoted history below it, the attribution
/// line that introduces that history, or the signature. Lines it answers inline stay, as quotes, between its answers.
public struct ReplyText: Equatable, Sendable {
    public enum Segment: Equatable, Sendable {
        /// Words the sender wrote.
        case text(String)
        /// Earlier words the sender answers right below them.
        case quote(String)
    }

    public let segments: [Segment]

    /// Reads the plain-text part when the message has one: it keeps quotes as `>` lines, and every client writes
    /// it. HTML alone is read with its blockquotes turned into `>` lines, so both take the same path.
    public init(body: MessageBody) {
        let text: String
        if let plain = body.plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = plain
        } else {
            text = Self.quotedText(fromHTML: body.html ?? "")
        }
        segments = Self.segments(of: text)
    }

    /// The new words alone, as a notification or a bubble's accessibility label reads them.
    public var text: String {
        segments.compactMap { segment in
            if case .text(let words) = segment { words } else { nil }
        }.joined(separator: "\n")
    }

    // MARK: - Lines

    private enum Line: Equatable {
        case words(String)
        case blank
        case quote(String)
        /// "On Monday, Dana wrote:", in the forms clients write it.
        case attribution
        /// "-- ", or a mobile client's "Sent from my iPhone".
        case signature
        /// A header or rule after which everything is the earlier message: "-----Original Message-----", a
        /// forwarded message, Outlook's "From: … Sent: …".
        case history
    }

    static func segments(of text: String) -> [Segment] {
        var lines = classify(text)
        if let history = lines.firstIndex(of: .history) { lines.removeSubrange(history...) }
        lines = dropSignatures(lines)
        lines = dropTrailingQuotes(lines)
        return group(lines)
    }

    private static func classify(_ text: String) -> [Line] {
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).filter { !bidiControls.contains($0) } }
        var lines: [Line] = raw.indices.map { index in
            let line = raw[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return .blank }
            if line.hasPrefix(">") { return .quote(unquoted(line)) }
            if line == "--" || signatureLines.contains(line) { return .signature }
            if historyMarkers.contains(where: { line.contains($0) })
                || line.count >= 8 && line.allSatisfy({ $0 == "_" })
            {
                return .history
            }
            if isHeaderBlock(at: index, in: raw) { return .history }
            return .words(line)
        }
        // An attribution is a line ending in a colon that names a date or an address, right above a quote.
        for index in lines.indices {
            guard case .words(let line) = lines[index], line.hasSuffix(":"),
                line.contains("@") || line.contains(where: \.isNumber) || line.hasSuffix("wrote:"),
                lines[(index + 1)...].first(where: { $0 != .blank }).map(isQuote) ?? false
            else { continue }
            lines[index] = .attribution
            // Clients wrap a long attribution: "On Monday, Dana Levi <" then "dana@example.com> wrote:".
            if index > 0, case .words(let above) = lines[index - 1], above.hasPrefix("On ") {
                lines[index - 1] = .attribution
            }
        }
        return lines.filter { $0 != .attribution }
    }

    /// "From:" with a "Sent:" or "Date:" in the lines just below: the header Outlook writes above the message it
    /// answers or forwards.
    private static func isHeaderBlock(at index: Int, in raw: [String]) -> Bool {
        let line = raw[index].trimmingCharacters(in: .whitespaces)
        guard fromPrefixes.contains(where: line.hasPrefix) else { return false }
        return raw[(index + 1)...].prefix(4).contains { next in
            let next = next.trimmingCharacters(in: .whitespaces)
            return datePrefixes.contains(where: next.hasPrefix)
        }
    }

    /// A signature runs from its delimiter until the next quote, or the end.
    private static func dropSignatures(_ lines: [Line]) -> [Line] {
        var kept: [Line] = []
        var inSignature = false
        for line in lines {
            if line == .signature {
                inSignature = true
            } else if isQuote(line) {
                inSignature = false
            }
            if !inSignature { kept.append(line) }
        }
        return kept
    }

    /// The history at the bottom goes; quotes with answers below them stay.
    private static func dropTrailingQuotes(_ lines: [Line]) -> [Line] {
        guard let lastWords = lines.lastIndex(where: { if case .words = $0 { true } else { false } }) else {
            return []
        }
        return Array(lines[...lastWords])
    }

    /// By now only words, quotes and blank lines are left. A blank line stays inside the block it falls in.
    private static func group(_ lines: [Line]) -> [Segment] {
        var blocks: [(isQuote: Bool, lines: [String])] = []
        for line in lines {
            let isQuote: Bool
            let words: String
            switch line {
            case .words(let text): (isQuote, words) = (false, text)
            case .quote(let text): (isQuote, words) = (true, text)
            case .blank: (isQuote, words) = (blocks.last?.isQuote ?? false, "")
            case .attribution, .signature, .history: continue
            }
            if blocks.last?.isQuote == isQuote {
                blocks[blocks.count - 1].lines.append(words)
            } else {
                blocks.append((isQuote, [words]))
            }
        }
        return blocks.compactMap { block in
            let joined = block.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !joined.isEmpty else { return nil }
            return block.isQuote ? .quote(joined) : .text(joined)
        }
    }

    private static func isQuote(_ line: Line) -> Bool {
        if case .quote = line { true } else { false }
    }

    /// `>> text` and `> > text` read as `text`.
    private static func unquoted(_ line: String) -> String {
        String(line.drop { $0 == ">" || $0 == " " })
    }

    // MARK: - HTML

    /// HTML as text, with each blockquote's lines prefixed by `>` for its depth. A Gmail signature becomes a "-- "
    /// line, and Outlook's reply header a history rule, so the line rules above apply to HTML too.
    static func quotedText(fromHTML html: String) -> String {
        let marked =
            html
            .replacing(/(?i)<div\b[^>]*\bclass="[^"]*\bgmail_signature\b[^"]*"[^>]*>/) { "<br>--<br>\($0.output)" }
            .replacing(/(?i)<[a-z]+\b[^>]*\bid="(appendonsend|divRplyFwdMsg)"[^>]*>/) {
                "<br>-----Original Message-----<br>\($0.output.0)"
            }
        var text = ""
        var depth = 0
        var rest = marked[...]
        while true {
            let next = rest.firstMatch(of: /(?i)<(\/?)blockquote\b[^>]*>/)
            let chunk = rest[..<(next?.range.lowerBound ?? rest.endIndex)]
            let words = HTMLEntities.plainText(fromHTML: String(chunk))
            if !words.isEmpty {
                let prefix = String(repeating: "> ", count: depth)
                text +=
                    "\n"
                    + words.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { prefix + $0 }.joined(separator: "\n") + "\n"
            }
            guard let next else { break }
            depth = max(0, depth + (next.output.1.isEmpty ? 1 : -1))
            rest = rest[next.range.upperBound...]
        }
        return text
    }

    // MARK: - Vocabulary

    private static let bidiControls: Set<Character> = [
        "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}",
        "\u{2068}", "\u{2069}",
    ]
    private static let signatureLines: Set<String> = [
        "Sent from my iPhone", "Sent from my iPad", "Sent from my Mac", "Get Outlook for iOS",
        "Get Outlook for Android",
        "Sent from Outlook for iOS", "Sent from Mail for Windows", "נשלח מה-iPhone שלי", "נשלח מה-iPad שלי",
        "נשלח מ-iPhone שלי",
    ]
    private static let historyMarkers = [
        "-----Original Message-----", "---------- Forwarded message", "Begin forwarded message:",
        "-------- Original Message --------", "---------- הודעה שהועברה", "-----הודעה מקורית-----",
    ]
    private static let fromPrefixes = ["From:", "מאת:"]
    private static let datePrefixes = ["Sent:", "Date:", "נשלח:", "תאריך:"]
}
