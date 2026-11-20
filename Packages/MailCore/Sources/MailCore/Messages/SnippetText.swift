/// The line of a message's words that a mailbox row, an alert or the watch previews, the same for every provider.
public enum SnippetText {
    /// A snippet's words on one line (`oneLine(_:)`). A provider that makes snippets from a plain part that is really
    /// markup, as Gmail does, hands over the tags too.
    public static func words(of snippet: String) -> String {
        oneLine(MessageBody.isMarkup(snippet) ? HTMLEntities.plainText(fromHTML: snippet) : snippet)
    }

    /// Text's words on one line, without the invisible characters marketing mail pads its preheader with so that a
    /// mail app's preview shows nothing after it (`InvisibleCharacters`), and so without the long gap they would
    /// leave between no-break spaces.
    public static func oneLine(_ text: String) -> String {
        InvisibleCharacters.removed(from: text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
