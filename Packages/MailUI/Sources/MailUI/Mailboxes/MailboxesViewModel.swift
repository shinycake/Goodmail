import Foundation
import MailCore
import Observation

/// The list of mailboxes, each with its unread count. With one account: the standard mailboxes, then the user's
/// labels. With several: the standard mailboxes blending every account, then each account's own Inbox and labels.
@Observable
public final class MailboxesViewModel {
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
        public var id: Mailbox { mailbox }
        public let mailbox: Mailbox
        public let title: String
        public let unreadCount: Int
        /// `#rrggbb` for a user label with a color.
        public let color: String?
    }

    public private(set) var directory = MailboxDirectory()
    /// The blend of every account's color, or the only account's.
    public let theme: Theme

    @ObservationIgnored private let directoryStream: () -> AsyncThrowingStream<MailboxDirectory, any Error>
    @ObservationIgnored private let navigate: (Route) -> Void
    @ObservationIgnored private let accounts: [Account]

    public init(
        accounts: [Account],
        directory: @escaping () -> AsyncThrowingStream<MailboxDirectory, any Error>,
        navigate: @escaping (Route) -> Void = { _ in }
    ) {
        directoryStream = directory
        self.navigate = navigate
        self.accounts = accounts
        theme = Theme(accountID: nil, among: accounts)
    }

    /// The groups to show, leaving out any with no rows.
    public var groups: [Group] {
        let mailboxes = Group(section: .mailboxes, items: Mailbox.standard.map { item(for: $0, color: nil) })
        let labels = directory.labels.map { item(for: $0.mailbox, color: $0.color) }
        guard accounts.count > 1 else {
            return [mailboxes, Group(section: .labels, items: labels)].filter { !$0.items.isEmpty }
        }
        return [mailboxes]
            + accounts.map { account in
                let inbox = item(for: Mailbox(labelID: SystemLabel.inbox, accountID: account.id), color: nil)
                return Group(
                    section: .account(account), items: [inbox] + labels.filter { $0.mailbox.accountID == account.id })
            }
    }

    private func item(for mailbox: Mailbox, color: String?) -> Item {
        Item(
            mailbox: mailbox, title: mailbox.title(labels: directory.labels),
            unreadCount: mailbox.showsUnreadCount ? directory.unreadCounts[mailbox] ?? 0 : 0, color: color)
    }

    /// Follows the store until the calling task is cancelled. A failure leaves the last directory in place.
    public func observe() async {
        do {
            for try await directory in directoryStream() { self.directory = directory }
        } catch {}
    }

    public func open(_ mailbox: Mailbox) {
        navigate(.mailbox(mailbox))
    }

    public func openSettings() {
        navigate(.settings)
    }

    /// A new message from the first account, until the composer offers a choice.
    public func compose() {
        guard let account = accounts.first else { return }
        navigate(.compose(Draft(accountID: account.id)))
    }
}
