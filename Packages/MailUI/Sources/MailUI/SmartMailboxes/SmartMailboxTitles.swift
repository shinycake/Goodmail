import Foundation
public import MailCore

extension SmartMailbox {
    /// What the sidebar and the box's list call it, in this device's language for the starting set.
    nonisolated public var title: String {
        switch name {
        case .unread:
            String(
                localized: "Unread", table: "SmartMailboxes", bundle: .module,
                comment: "Smart mailbox: every unread conversation")
        case .vips:
            String(
                localized: "VIPs", table: "SmartMailboxes", bundle: .module,
                comment:
                    "The people the reader marked as VIPs: their smart mailbox, and the header above their addresses")
        case .withAttachments:
            String(
                localized: "With Attachments", table: "SmartMailboxes", bundle: .module,
                comment: "Smart mailbox: conversations with files attached")
        case .custom(let name): name
        }
    }

    /// The sidebar's header above the boxes, which also names a box's list whose box is gone.
    nonisolated public static var sectionTitle: String {
        String(
            localized: "Smart Mailboxes", table: "SmartMailboxes", bundle: .module,
            comment: "Header above the reader's smart mailboxes in the sidebar")
    }
}

/// The SF Symbols the editor offers a smart mailbox.
enum SmartMailboxSymbols {
    static let all = [
        "gearshape", "magnifyingglass", "envelope.badge", "crown", "paperclip", "star", "flag", "person",
        "person.2", "briefcase", "house", "cart", "creditcard", "airplane", "calendar", "doc.text", "tag",
        "bell", "heart", "bolt",
    ]
}
