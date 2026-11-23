public import MailCore
import UIKit

extension Mailbox {
    /// The mailbox's name: a standard one's, or the user label's from `labels`. A pure lookup, so intents can name
    /// mailboxes off the main actor.
    nonisolated public func title(labels: [MailboxDirectory.Label]) -> String {
        switch labelID {
        case nil:
            String(
                localized: "All Mail", table: "Mailboxes", bundle: .module,
                comment: "Mailbox: every thread outside Spam and Trash")
        case SystemLabel.inbox:
            String(localized: "Inbox", table: "Mailboxes", bundle: .module, comment: "Mailbox title")
        case SystemLabel.starred:
            String(localized: "Starred", table: "Mailboxes", bundle: .module, comment: "Mailbox: starred threads")
        case SystemLabel.sent:
            String(localized: "Sent", table: "Mailboxes", bundle: .module, comment: "Mailbox: sent mail")
        case SystemLabel.draft:
            String(localized: "Drafts", table: "Mailboxes", bundle: .module, comment: "Mailbox: unsent drafts")
        case SystemLabel.spam: String(localized: "Spam", table: "Mailboxes", bundle: .module, comment: "Mailbox: spam")
        case SystemLabel.trash:
            String(
                localized: "mailbox.trash", defaultValue: "Trash", table: "Mailboxes", bundle: .module,
                comment: "Mailbox: deleted mail")
        case let id?: labels.first { $0.mailbox == self }?.name ?? id
        }
    }

    /// The standard mailboxes' names, as the mailbox list shows them, by label ID, for conditions on the mailbox a
    /// mail is in (`MailFacts.labelNames`).
    nonisolated public static var standardNames: [String: String] {
        Dictionary(
            standard.compactMap { mailbox in mailbox.labelID.map { ($0, mailbox.title(labels: [])) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// The title of this mailbox's list. One account's Inbox goes by the account's name, as in Apple Mail, so it reads
    /// apart from the other accounts' Inboxes; any other list by `title(labels:)`, as the large title has no room
    /// for an address beside it.
    nonisolated public func listTitle(labels: [MailboxDirectory.Label], accounts: [Account]) -> String {
        if labelID == SystemLabel.inbox, let account = accounts.first(where: { $0.id == accountID }) {
            return account.title
        }
        return title(labels: labels)
    }

    /// What the system calls a window showing this mailbox's list: `listTitle`, with one account's other standard
    /// mailboxes named with the account, as "Trash · me@example.com", so its window reads apart from the others'.
    nonisolated func windowListTitle(labels: [MailboxDirectory.Label], accounts: [Account]) -> String {
        let title = listTitle(labels: labels, accounts: accounts)
        guard isStandard, labelID != SystemLabel.inbox, let account = accounts.first(where: { $0.id == accountID })
        else { return title }
        return String(
            localized: "\(title) · \(account.title)", table: "Mailboxes", bundle: .module,
            comment: "Window title of one account's standard mailbox among several accounts, as Trash · me@example.com")
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
