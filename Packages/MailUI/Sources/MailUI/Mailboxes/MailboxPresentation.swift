import MailCore
import UIKit

extension Mailbox {
    /// The mailbox's name: a standard one's, or the user label's from `labels`.
    public func title(labels: [MailboxDirectory.Label]) -> String {
        switch labelID {
        case nil:
            String(localized: "All Mail", bundle: .module, comment: "Mailbox: every thread outside Spam and Trash")
        case SystemLabel.inbox: String(localized: "Inbox", bundle: .module, comment: "Mailbox title")
        case SystemLabel.starred: String(localized: "Starred", bundle: .module, comment: "Mailbox: starred threads")
        case SystemLabel.sent: String(localized: "Sent", bundle: .module, comment: "Mailbox: sent mail")
        case SystemLabel.draft: String(localized: "Drafts", bundle: .module, comment: "Mailbox: unsent drafts")
        case SystemLabel.spam: String(localized: "Spam", bundle: .module, comment: "Mailbox: spam")
        case SystemLabel.trash:
            String(localized: "mailbox.trash", defaultValue: "Trash", bundle: .module, comment: "Mailbox: deleted mail")
        case let id?: labels.first { $0.mailbox == self }?.name ?? id
        }
    }

    var symbol: String {
        switch labelID {
        case nil: "archivebox"
        case SystemLabel.inbox: "tray"
        case SystemLabel.starred: "star"
        case SystemLabel.sent: "paperplane"
        case SystemLabel.draft: "doc"
        case SystemLabel.spam: "xmark.bin"
        case SystemLabel.trash: "trash"
        default: "tag"
        }
    }

    /// Whether the mailbox list shows its unread count: only where unread mail is waiting to be read, so not in
    /// All Mail (it repeats the rest), Sent, Drafts, Spam or Trash.
    var showsUnreadCount: Bool {
        guard let labelID else { return false }
        return ![SystemLabel.sent, SystemLabel.draft, SystemLabel.spam, SystemLabel.trash].contains(labelID)
    }
}

extension UIColor {
    /// A user label's `#rrggbb` color.
    convenience init?(labelColor hex: String?) {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
