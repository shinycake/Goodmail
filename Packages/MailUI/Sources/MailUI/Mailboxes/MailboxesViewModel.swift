import Foundation
import MailCore
import Observation

/// The list of mailboxes: the standard ones, with Scheduled while a message waits there, then the user's labels,
/// each with its unread count.
@Observable
public final class MailboxesViewModel {
    /// Where a row leads.
    nonisolated public enum Destination: Hashable, Sendable {
        case mailbox(Mailbox)
        /// The messages waiting to be sent later.
        case scheduled
    }

    nonisolated public struct Item: Hashable, Identifiable, Sendable {
        public var id: Destination { destination }
        public let destination: Destination
        public let title: String
        public let symbol: String
        /// The number beside it: unread threads, or messages waiting to go. Zero shows none.
        public let count: Int
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
        var items = Mailbox.standard.map { item(for: $0, color: nil) }
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

    public var labelItems: [Item] {
        directory.labels.map { item(for: $0.mailbox, color: $0.color) }
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
        }
    }

    public func openSettings() {
        navigate(.settings)
    }

    public func compose() {
        guard let composingAccount else { return }
        navigate(.compose(Draft(accountID: composingAccount)))
    }
}
