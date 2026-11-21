import Foundation
import MailCore

extension ListFilter.Option {
    var title: String {
        switch self {
        case .unread:
            String(
                localized: "Filter.Unread", defaultValue: "Unread", table: "Mailbox", bundle: .module,
                comment: "List filter: only conversations not read yet")
        case .starred:
            String(
                localized: "Filter.Starred", defaultValue: "Starred", table: "Mailbox", bundle: .module,
                comment: "List filter: only conversations with a star")
        case .withAttachments:
            String(
                localized: "Filter.WithAttachments", defaultValue: "With Attachments", table: "Mailbox",
                bundle: .module, comment: "List filter: only conversations that carry files")
        }
    }

    var symbol: String {
        switch self {
        case .unread: "envelope.badge"
        case .starred: "star"
        case .withAttachments: "paperclip"
        }
    }
}

extension ListFilter {
    /// What the list is filtered by, in words for under its title, or `nil` while the filter is off.
    var summary: String? {
        choices.map { choices in
            Option.allCases.filter(choices.contains).map(\.title).formatted(.list(type: .and, width: .narrow))
        }
    }

    /// What an empty list says while the filter hides everything in it.
    var emptyTitle: String {
        switch choices ?? [] {
        case [.unread]:
            String(
                localized: "No Unread Mail", table: "Mailbox", bundle: .module,
                comment: "An empty list while only unread conversations are shown")
        case [.starred]:
            String(
                localized: "No Starred Mail", table: "Mailbox", bundle: .module,
                comment: "An empty list while only starred conversations are shown")
        case [.withAttachments]:
            String(
                localized: "No Mail with Attachments", table: "Mailbox", bundle: .module,
                comment: "An empty list while only conversations with files are shown")
        default:
            String(
                localized: "No Matching Mail", table: "Mailbox", bundle: .module,
                comment: "An empty list while several filters are on and no conversation meets them all")
        }
    }
}
