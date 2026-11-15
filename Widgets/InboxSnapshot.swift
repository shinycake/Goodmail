import Foundation
import MailCore
import MailStore

/// What the Inbox widget shows: the newest Inbox conversations, or why there are none.
enum InboxSnapshot: Sendable {
    case noAccounts
    /// The shared database couldn't be opened, as in an unsigned build without the App Group.
    case unavailable
    case inbox([Row])

    struct Row: Identifiable, Sendable {
        let thread: ThreadSummary
        /// The account's color, which marks the row while it is unread.
        let color: AccountColor

        var id: ThreadSummary.ID { thread.id }
    }

    /// As many rows as the largest widget shows.
    static let limit = 6

    static let placeholder = InboxSnapshot.inbox(
        (0..<limit).map { index in
            Row(
                thread: ThreadSummary(
                    id: ThreadSummary.ID(accountID: AccountID(rawValue: "placeholder"), threadID: "\(index)"),
                    subject: "Subject", snippet: "", sender: Contact(name: "Sender", address: ""), date: .now,
                    isUnread: index < 2, messageCount: 1, labelIDs: [SystemLabel.inbox]),
                color: .blue)
        })

    /// The shared database's newest Inbox conversations.
    static func load() -> InboxSnapshot {
        guard let database = WidgetDatabase.shared else { return .unavailable }
        do {
            let accounts = try database.accounts()
            guard !accounts.isEmpty else { return .noAccounts }
            let colors = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.color) })
            return .inbox(
                try database.threads(in: .inbox, limit: limit).map { thread in
                    Row(thread: thread, color: colors[thread.id.accountID] ?? .blue)
                })
        } catch {
            return .unavailable
        }
    }
}

/// The App Group's database, opened once per widget process; `nil` without the App Group.
enum WidgetDatabase {
    static let shared: MailDatabase? = SharedContainer.directoryURL.flatMap { directory in
        try? MailDatabase(url: directory.appending(path: "Mail/mail.sqlite"))
    }
}
