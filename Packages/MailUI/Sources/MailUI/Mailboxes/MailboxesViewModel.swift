import Foundation
import MailCore
import Observation

/// The list of mailboxes: the standard ones, then the user's labels, each with its unread count.
@Observable
public final class MailboxesViewModel {
    nonisolated public struct Item: Hashable, Identifiable, Sendable {
        public var id: Mailbox { mailbox }
        public let mailbox: Mailbox
        public let title: String
        public let unreadCount: Int
        /// `#rrggbb` for a user label with a color.
        public let color: String?
    }

    public private(set) var directory = MailboxDirectory()

    @ObservationIgnored private let directoryStream: () -> AsyncThrowingStream<MailboxDirectory, any Error>
    @ObservationIgnored private let navigate: (Route) -> Void
    @ObservationIgnored private let composingAccount: AccountID?

    public init(
        accounts: [Account],
        directory: @escaping () -> AsyncThrowingStream<MailboxDirectory, any Error>,
        navigate: @escaping (Route) -> Void = { _ in }
    ) {
        directoryStream = directory
        self.navigate = navigate
        composingAccount = accounts.first?.id
    }

    public var standardItems: [Item] {
        Mailbox.standard.map { item(for: $0, color: nil) }
    }

    public var labelItems: [Item] {
        directory.labels.map { item(for: $0.mailbox, color: $0.color) }
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

    public func compose() {
        guard let composingAccount else { return }
        navigate(.compose(Draft(accountID: composingAccount)))
    }
}
