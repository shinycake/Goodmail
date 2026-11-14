import Foundation
import MailCore
import Observation

/// The list of mailboxes, each with its unread count. With one account: the standard mailboxes, with Snoozed while
/// a thread sleeps and Scheduled while a message waits, then the user's labels. With several: the standard mailboxes
/// blending every account, then each account's own Inbox and labels.
@Observable
public final class MailboxesViewModel {
    /// Where a row leads.
    nonisolated public enum Destination: Hashable, Sendable {
        case mailbox(Mailbox)
        /// The messages waiting to be sent later.
        case scheduled
        /// The threads snoozed out of the Inbox.
        case snoozed
    }

    /// A group of rows, under its own header.
    nonisolated public enum Section: Hashable, Sendable {
        /// The standard mailboxes, spanning every account.
        case mailboxes
        /// The only account's labels.
        case labels
        /// One of several accounts: its Inbox, then its labels.
        case account(Account)
    }

    nonisolated public struct Group: Equatable, Sendable {
        public let section: Section
        public let items: [Item]
    }

    nonisolated public struct Item: Hashable, Identifiable, Sendable {
        public var id: Destination { destination }
        public let destination: Destination
        public let title: String
        public let symbol: String
        /// The number beside it: unread threads, or threads or messages waiting. Zero shows none.
        public let count: Int
        /// `#rrggbb` for a user label with a color.
        public let color: String?
    }

    public private(set) var directory = MailboxDirectory()
    /// What every account's mailboxes wear, or the only account's color.
    public let theme: Theme

    @ObservationIgnored private let directoryStream: () -> AsyncThrowingStream<MailboxDirectory, any Error>
    @ObservationIgnored private let navigate: (Route) -> Void
    @ObservationIgnored private let accounts: [Account]

    public init(
        accounts: [Account],
        directory: @escaping () -> AsyncThrowingStream<MailboxDirectory, any Error>,
        navigate: @escaping (Route) -> Void = { _ in },
        combinedTheme: CombinedTheme = Preferences.combinedTheme
    ) {
        directoryStream = directory
        self.navigate = navigate
        self.accounts = accounts
        theme = Theme(accountID: nil, among: accounts, combined: combinedTheme)
    }

    /// The groups to show, leaving out any with no rows.
    public var groups: [Group] {
        let mailboxes = Group(section: .mailboxes, items: standardItems)
        guard accounts.count > 1 else {
            let labels = directory.labels.map { item(for: $0.mailbox, color: $0.color) }
            return [mailboxes, Group(section: .labels, items: labels)].filter { !$0.items.isEmpty }
        }
        return [mailboxes]
            + accounts.map { account in
                let inbox = item(for: Mailbox(labelID: SystemLabel.inbox, accountID: account.id), color: nil)
                let labels = directory.labels.filter { $0.mailbox.accountID == account.id }
                    .map { item(for: $0.mailbox, color: $0.color) }
                return Group(section: .account(account), items: [inbox] + labels)
            }
    }

    /// The standard mailboxes, with Snoozed after Starred while a thread sleeps and Scheduled after Drafts while a
    /// message waits.
    private var standardItems: [Item] {
        var items = Mailbox.standard.map { item(for: $0, color: nil) }
        if directory.snoozedCount > 0, let starred = items.firstIndex(where: { $0.destination == .mailbox(.starred) }) {
            let snoozed = Item(
                destination: .snoozed,
                title: String(localized: "Snoozed", bundle: .module, comment: "Mailbox: threads snoozed until later"),
                symbol: "moon.zzz", count: directory.snoozedCount, color: nil)
            items.insert(snoozed, at: starred + 1)
        }
        if directory.scheduledCount > 0, let drafts = items.firstIndex(where: { $0.destination == .mailbox(.drafts) }) {
            let scheduled = Item(
                destination: .scheduled,
                title: String(
                    localized: "Scheduled", bundle: .module, comment: "Mailbox: messages waiting to be sent later"),
                symbol: "clock", count: directory.scheduledCount, color: nil)
            items.insert(scheduled, at: drafts + 1)
        }
        return items
    }

    private func item(for mailbox: Mailbox, color: String?) -> Item {
        Item(
            destination: .mailbox(mailbox), title: mailbox.title(labels: directory.labels), symbol: mailbox.symbol,
            count: mailbox.showsUnreadCount ? directory.unreadCounts[mailbox] ?? 0 : 0, color: color)
    }

    /// Follows the store until the calling task is cancelled. A failure leaves the last directory in place.
    public func observe() async {
        do {
            for try await directory in directoryStream() { self.directory = directory }
        } catch {}
    }

    public func open(_ destination: Destination) {
        switch destination {
        case .mailbox(let mailbox): navigate(.mailbox(mailbox))
        case .scheduled: navigate(.scheduled)
        case .snoozed: navigate(.snoozed)
        }
    }

    public func openSettings() {
        navigate(.settings)
    }

    /// A new message from the first account. The composer's From menu changes it.
    public func compose() {
        guard let account = accounts.first else { return }
        navigate(.compose(Draft(accountID: account.id)))
    }
}
