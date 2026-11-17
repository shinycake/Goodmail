public import MailCore

extension WristCommand.Kind {
    /// The mail action the iPhone runs for it; `nil` for a pin, which is the iPhone's own and not a mail action.
    public var threadAction: ThreadAction? {
        switch self {
        case .archive: .archive
        case .moveToInbox: .moveToInbox
        case .trash: .trash
        case .untrash: .untrash
        case .markRead(let read): .markRead(read)
        case .pin: nil
        }
    }
}
