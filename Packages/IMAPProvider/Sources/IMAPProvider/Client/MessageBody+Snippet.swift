import MailCore

extension MessageBody {
    /// The start of the body's words, on one line, as Gmail's snippets are.
    var snippet: String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200))
    }
}

/// The start of a message's words, as far as the bytes fetched for it reach.
enum Snippet: Equatable, Sendable {
    case found(String)
    /// The bytes ended before the first word, as when a long style sheet at the top of an HTML mail fills them.
    case pastFetchedBytes

    /// What the mailbox list shows.
    var text: String {
        switch self {
        case .found(let text): text
        case .pastFetchedBytes: ""
        }
    }
}
