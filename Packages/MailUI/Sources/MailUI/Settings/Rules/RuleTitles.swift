import Foundation
import MailCore

/// What the rules editor calls each field, test and action.
extension MailCore.TextField {
    var ruleTitle: String {
        switch self {
        case .subject:
            String(localized: "Subject", table: "RuleFields", bundle: .module, comment: "Rule field: subject")
        case .body:
            String(localized: "Message Text", table: "RuleFields", bundle: .module, comment: "Rule field: body text")
        case .snippet:
            String(localized: "Preview", table: "RuleFields", bundle: .module, comment: "Rule field: preview")
        case .sender:
            String(
                localized: "From", table: "RuleFields", bundle: .module, comment: "Rule field: sender name or address")
        case .senderName:
            String(localized: "Sender Name", table: "RuleFields", bundle: .module, comment: "Rule field: sender's name")
        case .senderAddress:
            String(
                localized: "Sender Address", table: "RuleFields", bundle: .module,
                comment: "Rule field: sender's address")
        case .senderDomain:
            String(
                localized: "Sender Domain", table: "RuleFields", bundle: .module, comment: "Rule field: sender's domain"
            )
        case .to: String(localized: "To", table: "RuleFields", bundle: .module, comment: "Rule field: To recipients")
        case .cc: String(localized: "Cc", table: "RuleFields", bundle: .module, comment: "Rule field: Cc recipients")
        case .bcc: String(localized: "Bcc", table: "RuleFields", bundle: .module, comment: "Rule field: Bcc recipients")
        case .replyTo:
            String(localized: "Reply-To", table: "RuleFields", bundle: .module, comment: "Rule field: Reply-To")
        case .recipients:
            String(
                localized: "Any Recipient", table: "RuleFields", bundle: .module, comment: "Rule field: To, Cc or Bcc")
        case .attachmentName:
            String(
                localized: "Attachment Name", table: "RuleFields", bundle: .module, comment: "Rule field: a file's name"
            )
        case .attachmentType:
            String(
                localized: "Attachment Type", table: "RuleFields", bundle: .module, comment: "Rule field: a file's type"
            )
        case .mailbox:
            String(localized: "Mailbox", table: "RuleFields", bundle: .module, comment: "Rule field: mailbox")
        case .account:
            String(localized: "Account", table: "RuleFields", bundle: .module, comment: "Rule field: account")
        case .unsubscribe:
            String(
                localized: "Unsubscribe Link", table: "RuleFields", bundle: .module, comment: "Rule field: list link")
        case .internetMessageID:
            String(
                localized: "Message-ID", table: "RuleFields", bundle: .module, comment: "Rule field: Message-ID header")
        }
    }
}

extension NumberField {
    var ruleTitle: String {
        switch self {
        case .toCount:
            String(localized: "Number of To", table: "RuleFields", bundle: .module, comment: "Rule field: To count")
        case .ccCount:
            String(localized: "Number of Cc", table: "RuleFields", bundle: .module, comment: "Rule field: Cc count")
        case .bccCount:
            String(localized: "Number of Bcc", table: "RuleFields", bundle: .module, comment: "Rule field: Bcc count")
        case .recipientCount:
            String(
                localized: "Number of Recipients", table: "RuleFields", bundle: .module,
                comment: "Rule field: all recipients")
        case .attachmentCount:
            String(
                localized: "Number of Attachments", table: "RuleFields", bundle: .module,
                comment: "Rule field: attachment count")
        case .attachmentSize:
            String(
                localized: "Attachments Size (MB)", table: "RuleFields", bundle: .module,
                comment: "Rule field: attachments' total size, in megabytes")
        case .messageCount:
            String(
                localized: "Messages in Conversation", table: "RuleFields", bundle: .module,
                comment: "Rule field: conversation length")
        case .bodyLength:
            String(
                localized: "Text Length", table: "RuleFields", bundle: .module,
                comment: "Rule field: characters in body")
        case .largestAmount:
            String(
                localized: "Highest Price", table: "RuleFields", bundle: .module, comment: "Rule field: largest amount")
        case .totalAmount:
            String(localized: "Total Price", table: "RuleFields", bundle: .module, comment: "Rule field: order total")
        }
    }
}

extension MailFlag {
    var ruleTitle: String {
        switch self {
        case .unread: String(localized: "Unread", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .starred: String(localized: "Flagged", table: "RuleFields", bundle: .module, comment: "Rule flag: starred")
        case .important: String(localized: "Important", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .hasAttachments:
            String(localized: "Has Attachments", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .inInbox: String(localized: "In Inbox", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .archived: String(localized: "Archived", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .inSpam: String(localized: "In Spam", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .inTrash: String(localized: "In Trash", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .draft: String(localized: "Draft", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .fromMe: String(localized: "From Me", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .toMe: String(localized: "Addressed to Me", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .reply:
            String(localized: "A Reply", table: "RuleFields", bundle: .module, comment: "Rule flag: subject has Re:")
        case .forward:
            String(localized: "A Forward", table: "RuleFields", bundle: .module, comment: "Rule flag: subject has Fwd:")
        case .pinned: String(localized: "Pinned", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .snoozed: String(localized: "Snoozed", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .muted: String(localized: "Muted", table: "RuleFields", bundle: .module, comment: "Rule flag")
        case .hasUnsubscribe:
            String(localized: "From a Mailing List", table: "RuleFields", bundle: .module, comment: "Rule flag")
        }
    }
}

extension ConditionDraft.TextTest {
    var title: String {
        switch self {
        case .contains: String(localized: "Contains", table: "RuleFields", bundle: .module, comment: "Text test")
        case .doesNotContain:
            String(localized: "Doesn’t Contain", table: "RuleFields", bundle: .module, comment: "Text test")
        case .equals: String(localized: "Is", table: "RuleFields", bundle: .module, comment: "Text test: equals")
        case .beginsWith: String(localized: "Begins With", table: "RuleFields", bundle: .module, comment: "Text test")
        case .endsWith: String(localized: "Ends With", table: "RuleFields", bundle: .module, comment: "Text test")
        case .matchesPattern:
            String(
                localized: "Matches Pattern", table: "RuleFields", bundle: .module,
                comment: "Text test: a regular expression")
        case .isEmpty: String(localized: "Is Empty", table: "RuleFields", bundle: .module, comment: "Text test")
        case .isNotEmpty: String(localized: "Isn’t Empty", table: "RuleFields", bundle: .module, comment: "Text test")
        }
    }
}

extension ConditionDraft.NumberTest {
    var title: String {
        switch self {
        case .equals: String(localized: "Is", table: "RuleFields", bundle: .module, comment: "Number test: equals")
        case .lessThan: String(localized: "Less Than", table: "RuleFields", bundle: .module, comment: "Number test")
        case .greaterThan: String(localized: "More Than", table: "RuleFields", bundle: .module, comment: "Number test")
        case .atMost: String(localized: "At Most", table: "RuleFields", bundle: .module, comment: "Number test")
        case .atLeast: String(localized: "At Least", table: "RuleFields", bundle: .module, comment: "Number test")
        }
    }
}

extension TimeUnit {
    var title: String {
        switch self {
        case .hours: String(localized: "Hours", table: "RuleFields", bundle: .module, comment: "Length unit")
        case .days: String(localized: "Days", table: "RuleFields", bundle: .module, comment: "Length unit")
        case .weeks: String(localized: "Weeks", table: "RuleFields", bundle: .module, comment: "Length unit")
        }
    }
}

/// The kinds of condition and action the editor's Add menus offer, each with a starting value.
enum RuleChoices {
    static var conditions: [(title: String, symbol: String, kind: ConditionDraft.Kind)] {
        [
            (
                String(localized: "Text", table: "RuleFields", bundle: .module, comment: "Add a text condition"),
                "textformat", .text(.sender, .contains, "")
            ),
            (
                String(localized: "Number", table: "RuleFields", bundle: .module, comment: "Add a number condition"),
                "number", .number(.ccCount, .atLeast, "")
            ),
            (
                String(localized: "Status", table: "RuleFields", bundle: .module, comment: "Add a yes/no condition"),
                "checkmark.circle", .flag(.hasAttachments, true)
            ),
            (
                String(
                    localized: "Day of the Week", table: "RuleFields", bundle: .module,
                    comment: "Add a weekday condition"),
                "calendar", .weekdays([])
            ),
            (
                String(localized: "Time of Day", table: "RuleFields", bundle: .module, comment: "Add a time condition"),
                "clock", .timeOfDay(from: TimeOfDay(hour: 9, minute: 0), to: TimeOfDay(hour: 17, minute: 0))
            ),
            (
                String(
                    localized: "Received Within", table: "RuleFields", bundle: .module,
                    comment: "Add a recency condition"),
                "hourglass", .receivedWithin(1, .days)
            ),
            (
                String(localized: "Label", table: "RuleFields", bundle: .module, comment: "Add a label condition"),
                "tag", .label("")
            ),
        ]
    }

    static var actions: [ActionDraft.Kind] {
        [
            .markRead, .star, .markImportant, .pin, .archive, .move(toLabel: ""), .addLabel(""), .snooze(1, .days),
            .mute, .reportSpam, .trash, .notify(keyword: ""),
        ]
    }
}

extension ActionDraft.Kind {
    var title: String {
        switch self {
        case .markRead: String(localized: "Mark as Read", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .star: String(localized: "Flag", table: "RuleFields", bundle: .module, comment: "Rule action: star")
        case .markImportant:
            String(localized: "Mark as Important", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .archive: String(localized: "Archive", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .trash: String(localized: "Move to Trash", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .reportSpam: String(localized: "Report Spam", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .pin: String(localized: "Pin", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .mute: String(localized: "Mute", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .move: String(localized: "Move to Label", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .addLabel: String(localized: "Add Label", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .snooze: String(localized: "Snooze", table: "RuleFields", bundle: .module, comment: "Rule action")
        case .notify:
            String(
                localized: "Notify with Keyword", table: "RuleFields", bundle: .module,
                comment: "Rule action: posts a notification a Shortcuts automation can watch for")
        }
    }

    var symbol: String {
        switch self {
        case .markRead: "envelope.open"
        case .star: "flag"
        case .markImportant: "exclamationmark.circle"
        case .archive: "archivebox"
        case .trash: "trash"
        case .reportSpam: "xmark.bin"
        case .pin: "pin"
        case .mute: "bell.slash"
        case .move: "folder"
        case .addLabel: "tag"
        case .snooze: "moon.zzz"
        case .notify: "bell.badge"
        }
    }
}
