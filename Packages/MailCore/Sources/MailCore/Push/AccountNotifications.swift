import Foundation

/// Which new mail in an account's Inbox alerts the reader.
public enum NotificationLevel: String, CaseIterable, Codable, Sendable {
    /// Everything new in the Inbox.
    case all
    /// Only what the service sorts as Primary. Offered for services with Inbox categories.
    case primary
    /// Nothing. The device also stops asking the relay to wake it for the account.
    case off
}

/// One account's alert choice, and how far its new mail has been considered for alerts.
public struct AccountNotifications: Equatable, Sendable {
    /// How far back a first alert reaches, so the push that arrives right after setup still shows its mail.
    public static let firstLookback: TimeInterval = 15 * 60

    public var level: NotificationLevel
    /// Mail dated at or before this already alerted, or was seen in the app. Only newer mail alerts.
    public var seenThrough: Date

    public init(level: NotificationLevel, seenThrough: Date) {
        self.level = level
        self.seenThrough = seenThrough
    }

    /// An account that never alerted: everything new alerts.
    public static func initial(at now: Date) -> AccountNotifications {
        AccountNotifications(level: .all, seenThrough: now.addingTimeInterval(-firstLookback))
    }

    /// The threads among `arrived` that alert at this level, newest first, and how far the account's mail has been
    /// considered once they have.
    ///
    /// A thread alerts when it is in the Inbox, unread, newer than `seenThrough`, and its latest message is from
    /// someone else. Read-state and label changes refetch a thread without making it newer, so they never alert.
    public func alerts(among arrived: [ThreadSummary], in account: Account) -> (
        threads: [ThreadSummary], seenThrough: Date
    ) {
        let inbox = arrived.filter { $0.labelIDs.contains(SystemLabel.inbox) }
        let considered = max(seenThrough, inbox.map(\.date).max() ?? seenThrough)
        let threads = inbox.filter { thread in
            thread.isUnread && thread.date > seenThrough
                && thread.sender.address.caseInsensitiveCompare(account.email) != .orderedSame
                && alerts(for: thread)
        }
        return (threads.sorted { $0.date > $1.date }, considered)
    }

    private func alerts(for thread: ThreadSummary) -> Bool {
        switch level {
        case .all: true
        case .primary: InboxCategory(of: thread) == .primary
        case .off: false
        }
    }
}

extension MailService {
    /// Whether the service tells the push relay about new mail, so the device can alert for it. iCloud has no
    /// third-party push.
    public var pushesNewMail: Bool {
        switch self {
        case .gmail, .outlook: true
        case .icloud: false
        }
    }
}
