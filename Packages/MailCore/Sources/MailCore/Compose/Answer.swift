import Foundation

/// How the reader answers a thread: to its sender, to everyone on it, on to someone new, or as a new message of
/// its own.
public enum Answer: Hashable, Sendable {
    case reply
    case replyAll
    case forward
    /// A forward that attaches the original whole, as a `.eml` file.
    case forwardAsAttachment
    /// A new message copied from one in the thread.
    case editAsNew

    /// The draft that answers the newest message of `messages` that was sent, not one still a draft. Edit as New
    /// copies the newest one the account itself sent, when it sent any. `nil` when there is none. `wording` is the
    /// quote's language.
    public func draft(answering messages: [Message], accountEmail: String, wording: QuoteWording) -> Draft? {
        let sent = messages.filter { !$0.labelIDs.contains(SystemLabel.draft) }
        guard let message = sent.last else { return nil }
        return switch self {
        case .reply: .reply(to: message, all: false, accountEmail: accountEmail, wording: wording)
        case .replyAll: .reply(to: message, all: true, accountEmail: accountEmail, wording: wording)
        case .forward: .forward(message, wording: wording)
        case .forwardAsAttachment: .forwardAsAttachment(message, wording: wording)
        case .editAsNew:
            .editAsNew(
                sent.last { $0.from.address.caseInsensitiveCompare(accountEmail) == .orderedSame } ?? message)
        }
    }
}
