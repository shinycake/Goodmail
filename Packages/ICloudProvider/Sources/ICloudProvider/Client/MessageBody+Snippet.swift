import MailCore

extension MessageBody {
    /// The start of the body's words, on one line, as Gmail's snippets are.
    var snippet: String {
        let text = plain ?? html.map(HTMLEntities.plainText(fromHTML:)) ?? ""
        return String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200))
    }
}
