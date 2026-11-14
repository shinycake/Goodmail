import Foundation

/// How the reader answers a thread: to its sender, to everyone on it, or on to someone new.
public enum Answer: Hashable, Sendable {
    case reply
    case replyAll
    case forward

    /// The draft that answers the newest message of `messages` that was sent, not one still a draft. `nil` when
    /// there is none. `wording` is the quote's language.
    public func draft(answering messages: [Message], accountEmail: String, wording: QuoteWording) -> Draft? {
        guard let message = messages.last(where: { !$0.labelIDs.contains(SystemLabel.draft) }) else { return nil }
        return switch self {
        case .reply: .reply(to: message, all: false, accountEmail: accountEmail, wording: wording)
        case .replyAll: .reply(to: message, all: true, accountEmail: accountEmail, wording: wording)
        case .forward: .forward(message, wording: wording)
        }
    }
}
