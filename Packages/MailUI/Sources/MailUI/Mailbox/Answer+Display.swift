import MailCore

/// How each answer reads in a menu, in the mailbox list's and the reader's alike.
extension Answer {
    var title: String {
        switch self {
        case .reply:
            String(localized: "Reply", table: "Mailbox", bundle: .module, comment: "Composer title for a reply")
        case .replyAll:
            String(localized: "Reply All", table: "Mailbox", bundle: .module, comment: "Replies to everyone")
        case .forward: String(localized: "Forward", table: "Mailbox", bundle: .module, comment: "Forwards the message")
        case .forwardAsAttachment:
            String(
                localized: "Forward as Attachment", table: "Mailbox", bundle: .module,
                comment: "Forwards the whole message as a file attached to a new one")
        case .editAsNew:
            String(
                localized: "Edit as New", table: "Mailbox", bundle: .module,
                comment: "Opens a copy of the message as a new message to change and send")
        }
    }

    var symbol: String {
        switch self {
        case .reply: "arrowshape.turn.up.left"
        case .replyAll: "arrowshape.turn.up.left.2"
        case .forward: "arrowshape.turn.up.right"
        case .forwardAsAttachment: "paperclip"
        case .editAsNew: "square.and.pencil"
        }
    }
}
