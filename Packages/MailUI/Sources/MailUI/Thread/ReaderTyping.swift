import MailCore

/// What the keyboard types into in the reader, which decides the shortcuts the reader leaves to the text. On the
/// Mac the menu's keys win over the text, so ⌘⌫, which deletes to the line's start, would trash the conversation.
enum ReaderTyping: Equatable {
    /// Nothing in the reader takes typing: the shortcuts act on the conversation.
    case conversation
    /// The chat's reply field, and whether it holds something to send.
    case reply(sendable: Bool)
    /// The find bar's field.
    case find

    /// What typing makes of `command` ahead of the conversation, or `nil` where the conversation answers it. Send
    /// sends the reply being typed. Archive, Move to Trash and Erase Trash are dimmed rather than passed on, since the
    /// list behind would answer them for the same conversation, and a dimmed item leaves its keys to the text.
    func answer(to command: MailCommand, send: @escaping () -> Void) -> CommandAnswer? {
        switch command {
        case .send:
            guard case .reply(let sendable) = self else { return nil }
            return sendable ? .ready(perform: send) : .unavailable
        case .archive, .trash, .eraseTrash:
            return self == .conversation ? nil : .unavailable
        default:
            return nil
        }
    }
}
