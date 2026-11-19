import Foundation
import GRDB
public import MailCore

/// Which delivered alerts the reader has dealt with, and when that may have changed.
extension MailDatabase {
    /// The identifiers of the `alerts` whose mail no longer needs them, as `DeliveredAlert.Kind` says for each:
    /// read, filed out of the Inbox, deleted, or gone from the store, however the change reached it.
    public func handledAlerts(_ alerts: [DeliveredAlert]) throws -> [String] {
        try pool.read { db in
            try alerts.filter { alert in
                try Self.isHandled(alert, thread: Self.thread(alert.thread, in: db))
            }
            .map(\.identifier)
        }
    }

    /// How far a thread's date may fall before its alert's delivery and still be the alerted mail: the relay alerts
    /// within seconds of a sync, and a server's date can run a little behind.
    static let deliveryLag: TimeInterval = 10 * 60

    private static func isHandled(_ alert: DeliveredAlert, thread: ThreadSummary?) -> Bool {
        guard let thread else { return alert.kind != .relayed }
        // A push shown as sent came because its mail wasn't stored: a copy older than the alert is the thread as it
        // was before, read or filed, and says nothing of the new mail.
        if alert.kind == .relayed && thread.date < alert.deliveredAt.addingTimeInterval(-deliveryLag) { return false }
        if !thread.isUnread { return true }
        return switch alert.kind {
        case .newMail, .relayed: !thread.labelIDs.contains(SystemLabel.inbox)
        case .rule: !thread.labelIDs.isDisjoint(with: [SystemLabel.trash, SystemLabel.spam])
        }
    }

    /// Emits now and again each time a thread may have been read, filed or deleted: whenever which threads are
    /// unread, in the Inbox, in Trash or in Spam changes, in this process or another. Another sync touching the
    /// same threads emits nothing, so a sweep of delivered alerts runs only when one could have been dealt with.
    public func handlingChanges() -> AsyncThrowingStream<HandlingMark, any Error> {
        observe { db in try HandlingMark(in: db) }
    }
}

/// What decides whether alerts are handled, summed up small: for unread threads and for each of the Inbox, Trash and
/// Spam, how many threads there are and the total of their row IDs. A thread entering or leaving any of them moves
/// its sums; a thread's row ID stays the same as syncs update it.
public struct HandlingMark: Equatable, Sendable {
    /// How many unread threads, and the total of their row IDs.
    private let unread: [Double]
    /// The same for each label among the Inbox, Trash and Spam that holds any thread.
    private let labels: [String: [Double]]

    init(in db: Database) throws {
        let unread = try Row.fetchOne(db, sql: "SELECT COUNT(*), TOTAL(rowid) FROM thread WHERE isUnread")
        self.unread = unread.map { [$0[0], $0[1]] } ?? []
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT threadLabel.labelID, COUNT(*), TOTAL(thread.rowid) FROM threadLabel
                JOIN thread ON thread.accountID = threadLabel.accountID AND thread.id = threadLabel.threadID
                WHERE threadLabel.labelID IN (?, ?, ?)
                GROUP BY threadLabel.labelID
                """,
            arguments: [SystemLabel.inbox, SystemLabel.trash, SystemLabel.spam])
        labels = Dictionary(uniqueKeysWithValues: rows.map { ($0[0] as String, [$0[1], $0[2]]) })
    }
}
