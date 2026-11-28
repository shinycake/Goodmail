import Foundation
import GRDB
public import MailCore

extension MailDatabase {
    static func fetchDirectory(_ db: Database) throws -> MailboxDirectory {
        let labels =
            try LabelRecord
            .filter(Column("kind") == MailLabel.Kind.user.rawValue && Column("isHidden") == false)
            .fetchAll(db)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let userLabels = Set(labels.map { Mailbox(labelID: $0.id, accountID: AccountID(rawValue: $0.accountID)) })

        let inFocus = Set(try String.fetchAll(db, sql: "SELECT id FROM account WHERE inFocus"))
        var counts: [Mailbox: Int] = [:]
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT thread.accountID, threadLabel.labelID, COUNT(*) AS unread FROM thread
                JOIN threadLabel ON threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                WHERE thread.isUnread
                GROUP BY thread.accountID, threadLabel.labelID
                """)
        for row in rows {
            let own = Mailbox(labelID: row["labelID"], accountID: AccountID(rawValue: row["accountID"]))
            let unread: Int = row["unread"]
            // A user label counts in its own account; a system label counts in its account and, while the Focus shows
            // the account, in the blend of every account's.
            counts[own, default: 0] += unread
            if !userLabels.contains(own), inFocus.contains(row["accountID"]) {
                counts[Mailbox(labelID: own.labelID), default: 0] += unread
            }
        }
        let allMailUnread = try threadSelection(in: .allMail).unreadCount(in: db)
        if allMailUnread > 0 { counts[.allMail] = allMailUnread }
        let scheduled =
            try Int.fetchOne(
                db,
                sql:
                    "SELECT COUNT(*) FROM outgoing WHERE purpose = ? AND \(OutgoingMessage.Delivery.Stage.queued.condition)",
                arguments: [OutgoingMessage.Purpose.scheduledSend.rawValue]) ?? 0
        let snoozed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snooze WHERE wakeAt IS NOT NULL") ?? 0

        return MailboxDirectory(
            labels: labels.map { record in
                MailboxDirectory.Label(
                    mailbox: Mailbox(labelID: record.id, accountID: AccountID(rawValue: record.accountID)),
                    name: record.name, color: record.color)
            },
            unreadCounts: counts, scheduledCount: scheduled, snoozedCount: snoozed)
    }
}

extension MailFollowing {
    /// The user labels and unread counts for the mailbox list. Emits now and after every change.
    public func mailboxDirectory() -> AsyncThrowingStream<MailboxDirectory, any Error> {
        followed.observe { db in try MailDatabase.fetchDirectory(db) }
    }
}
