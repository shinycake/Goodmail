import Foundation

/// The words a message adds to its conversation: its body without the quoted history below it, the attribution
/// line that introduces that history, or the signature. Lines it answers inline stay, as quotes, between its answers.
public struct ReplyText: Equatable, Sendable {
    public enum Segment: Equatable, Sendable {
        /// Words the sender wrote, with the bold, italics and links their HTML gave them.
        case text(StyledText)
        /// Earlier words the sender answers right below them.
        case quote(String)
    }

    public let segments: [Segment]
    /// Whether the message forwards another: a forward's header comes before anything it answers, quoted or not, as
    /// Apple Mail quotes the whole message it forwards.
    public let forwards: Bool

    /// Reads the part `MessageBody.reading` picks. HTML is read with its blockquotes turned into `>` lines, so both
    /// take the same path.
    public init(body: MessageBody) {
        let text: StyledText =
            switch body.reading {
            case .plain(let plain): StyledText.linking(plain)
            case .html(let html): Self.quotedText(fromHTML: html)
            case .empty: StyledText()
            }
        let lines = Self.classify(text)
        segments = Self.segments(of: lines)
        forwards = Self.forwards(lines)
    }

    /// The new words alone, as a notification or a bubble's accessibility label reads them.
    public var text: String {
        segments.compactMap { segment in
            if case .text(let words) = segment { words.plain } else { nil }
        }.joined(separator: "\n")
    }

    // MARK: - Lines

    private enum Line: Equatable {
        case words(StyledText)
        case blank
        case quote(String)
        /// "On Monday, Dana wrote:", in the forms clients write it.
        case attribution
        /// "-- ", or a mobile client's "Sent from my iPhone".
        case signature
        /// A header or rule after which everything is the earlier message: "-----Original Message-----", a
        /// forwarded message, Outlook's "From: … Sent: …".
        case history(String)
    }

    static func segments(of text: StyledText) -> [Segment] {
        segments(of: classify(text))
    }

    private static func segments(of classified: [Line]) -> [Segment] {
        var lines = classified.filter { $0 != .attribution }
        if let history = lines.firstIndex(where: { if case .history = $0 { true } else { false } }) {
            lines.removeSubrange(history...)
        }
        lines = dropSignatures(lines)
        lines = dropTrailingQuotes(lines)
        return group(lines)
    }

    private static func classify(_ text: StyledText) -> [Line] {
        let rich = text.filter { !bidiControls.contains($0) }.mapRuns {
            $0.replacingOccurrences(of: "\r\n", with: "\n")
        }
        .split(separator: "\n")
        let raw = rich.map(\.plain)
        var lines: [Line] = raw.indices.map { index in
            let line = raw[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return .blank }
            if line.hasPrefix(">") { return .quote(unquoted(line)) }
            if line == "--" || signatureLines.contains(line) { return .signature }
            if historyMarkers.contains(where: { line.contains($0) })
                || line.count >= 8 && line.allSatisfy({ $0 == "_" })
            {
                return .history(line)
            }
            if isHeaderBlock(at: index, in: raw) { return .history(line) }
            return .words(rich[index].trimmingCharacters(in: .whitespaces))
        }
        // An attribution is a line ending in a colon that names a date or an address, right above a quote.
        for index in lines.indices {
            guard case .words(let words) = lines[index], case let line = words.plain, line.hasSuffix(":"),
                line.contains("@") || line.contains(where: \.isNumber) || line.hasSuffix("wrote:"),
                lines[(index + 1)...].first(where: { $0 != .blank }).map(isQuote) ?? false
            else { continue }
            lines[index] = .attribution
            // Clients wrap a long attribution: "On Monday, Dana Levi <" then "dana@example.com> wrote:".
            if index > 0, case .words(let above) = lines[index - 1], above.plain.hasPrefix("On ") {
                lines[index - 1] = .attribution
            }
        }
        return lines
    }

    /// A forward's header opens the first earlier message the body holds, quoted or not. Anything else there, such as
    /// an attribution, "-----Original Message-----" or "On … wrote:" in a quote, makes it a reply, whatever it quotes.
    private static func forwards(_ lines: [Line]) -> Bool {
        for line in lines {
            switch line {
            case .attribution: return false
            case .quote(let text) where text.isEmpty: continue
            case .quote(let text), .history(let text): return forwardMarkers.contains(where: text.contains)
            case .words, .blank, .signature: continue
            }
        }
        return false
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
        var blocks: [(isQuote: Bool, lines: [StyledText])] = []
        for line in lines {
            let isQuote: Bool
            let words: StyledText
            switch line {
            case .words(let text): (isQuote, words) = (false, text)
            case .quote(let text): (isQuote, words) = (true, StyledText(text))
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
            let joined = StyledText.joined(block.lines, separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !joined.isEmpty else { return nil }
            return block.isQuote ? .quote(joined.plain) : .text(joined)
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
    static func quotedText(fromHTML html: String) -> StyledText {
        let marked =
            html
            .replacing(/(?i)<div\b[^>]*\bclass="[^"]*\bgmail_signature\b[^"]*"[^>]*>/) { "<br>--<br>\($0.output)" }
            .replacing(/(?i)<[a-z]+\b[^>]*\bid="(appendonsend|divRplyFwdMsg)"[^>]*>/) {
                "<br>-----Original Message-----<br>\($0.output.0)"
            }
        var text = StyledText()
        var depth = 0
        var rest = marked[...]
        while true {
            let next = rest.firstMatch(of: /(?i)<(\/?)blockquote\b[^>]*>/)
            let chunk = rest[..<(next?.range.lowerBound ?? rest.endIndex)]
            let words = HTMLEntities.styledText(fromHTML: String(chunk))
            if !words.isEmpty {
                let prefix = StyledText(String(repeating: "> ", count: depth))
                text.append("\n")
                text.append(StyledText.joined(words.split(separator: "\n").map { prefix + $0 }, separator: "\n"))
                text.append("\n")
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
    /// The lines clients put above a message they forward, in English and Hebrew.
    private static let forwardMarkers = [
        "---------- Forwarded message", "Begin forwarded message:", "---------- הודעה שהועברה",
    ]
    private static let historyMarkers =
        forwardMarkers + [
            "-----Original Message-----", "-------- Original Message --------", "-----הודעה מקורית-----",
        ]
    private static let fromPrefixes = ["From:", "מאת:"]
    private static let datePrefixes = ["Sent:", "Date:", "נשלח:", "תאריך:"]
}
