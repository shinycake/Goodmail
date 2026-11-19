public import MailCore

/// A message too long or too laid out for a bubble, such as a newsletter or a forward: its subject and its words,
/// which the watch shows in full on a screen of their own.
public struct WristLetter: Codable, Equatable, Sendable {
    /// How much of the message `words` holds.
    public enum Extent: Codable, Equatable, Sendable {
        /// Every word of it.
        case whole
        /// Only its start, as when the whole conversation was too big for the iPhone to send; the rest reads there.
        case start
    }

    /// How many characters the bubble shows before the letter opens.
    static let previewLength = 300
    /// How many characters a code or the language is looked for in, as a reader sees them before scrolling.
    static let startLength = 1000

    public var subject: String
    public var words: StyledText
    public var extent: Extent

    public init(subject: String, words: StyledText, extent: Extent) {
        self.subject = subject
        self.words = words
        self.extent = extent
    }

    /// The first words, for the bubble.
    public var preview: StyledText { words.prefix(Self.previewLength) }

    /// The words a line at a time, each blank line kept as an empty one, so a screen lays out a long letter only as
    /// far as it scrolls: HTML puts each block on one line.
    public var lines: [StyledText] { words.split(separator: "\n") }

    /// The letter cut to its first characters that take at most `bytes` in UTF-8, keeping at least `minimum`
    /// characters; itself when it already fits.
    func cut(toBytes bytes: Int, minimum: Int) -> WristLetter {
        var count = 0
        var used = 0
        for character in words.plain {
            used += character.utf8.count
            if used > bytes, count >= minimum { break }
            count += 1
        }
        guard count < words.plain.count else { return self }
        return WristLetter(subject: subject, words: words.prefix(count), extent: .start)
    }
}
