import Foundation
public import MailCore

extension MailCommand {
    /// The command's name in the menu bar, in the list Command shows and for Full Keyboard Access. A screen may say
    /// it otherwise for what the command does there now (`CommandAnswer.ready`).
    public var title: String {
        switch self {
        case .settings:
            String(localized: "Settings…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .newMessage:
            String(localized: "New Message", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .newWindow:
            String(localized: "New Viewer Window", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .openInNewWindow:
            String(localized: "Open in New Window", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .exportPDF:
            String(localized: "Export as PDF…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .print:
            String(localized: "Print…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .closeWindow:
            String(localized: "Close Window", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .search:
            String(localized: "Search Mail", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .attachFiles:
            String(localized: "Attach Files…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .addLink:
            String(localized: "Add Link…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .switchLayout:
            String(localized: "Show as Chat", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .showPrimary: InboxCategory.primary.title
        case .showPromotions: InboxCategory.promotions.title
        case .showSocial: InboxCategory.social.title
        case .showUpdates: InboxCategory.updates.title
        case .showForums: InboxCategory.forums.title
        case .showCopyFields:
            String(localized: "Show Cc and Bcc", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .getMail:
            String(localized: "Get New Mail", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .eraseTrash:
            String(localized: "Erase Trash…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .send:
            String(localized: "Send", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .sendLater:
            String(localized: "Send Later…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .reply:
            String(localized: "Reply", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .replyAll:
            String(localized: "Reply All", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .forward:
            String(localized: "Forward", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .forwardAsAttachment:
            String(localized: "Forward as Attachment", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .editAsNew:
            String(localized: "Edit as New", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .archive:
            String(localized: "Archive", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .trash:
            String(localized: "Move to Trash", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .reportSpam:
            String(localized: "Report Spam", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .move:
            String(localized: "Move to…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .changeLabels:
            String(localized: "Label…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .snooze:
            String(localized: "Snooze…", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .markRead:
            String(localized: "Mark as Unread", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .star:
            String(localized: "Star", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .pin:
            String(localized: "Pin", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .mute:
            String(localized: "Mute", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .previousThread:
            String(localized: "Previous Conversation", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .nextThread:
            String(localized: "Next Conversation", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .strikethrough:
            String(localized: "Strikethrough", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .bulletedList:
            String(localized: "Bulleted List", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .numberedList:
            String(localized: "Numbered List", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .increaseQuoteLevel:
            String(localized: "Increase Quote Level", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        case .decreaseQuoteLevel:
            String(localized: "Decrease Quote Level", table: "Keyboard", bundle: .module, comment: "Menu bar command")
        }
    }
}

extension MenuBarMenu {
    /// The title of a menu the app adds itself.
    var title: String {
        switch self {
        case .application:
            String(localized: "Goodmail", table: "Keyboard", bundle: .module, comment: "Menu bar menu")
        case .file:
            String(localized: "File", table: "Keyboard", bundle: .module, comment: "Menu bar menu")
        case .edit:
            String(localized: "Edit", table: "Keyboard", bundle: .module, comment: "Menu bar menu")
        case .view:
            String(localized: "View", table: "Keyboard", bundle: .module, comment: "Menu bar menu")
        case .mailbox:
            String(localized: "Mailbox", table: "Keyboard", bundle: .module, comment: "Menu bar menu")
        case .message:
            String(localized: "Message", table: "Keyboard", bundle: .module, comment: "Menu bar menu")
        case .format:
            String(localized: "Format", table: "Keyboard", bundle: .module, comment: "Menu bar menu")
        }
    }
}
