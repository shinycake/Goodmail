import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// The user labels and unread counts for the mailbox list. Emits now and after every change.
    public func mailboxDirectory() -> AsyncThrowingStream<MailboxDirectory, any Error> {
        observe { db in try Self.fetchDirectory(db) }
    }

    static func fetchDirectory(_ db: Database) throws -> MailboxDirectory {
        let labels =
            try LabelRecord
            .filter(Column("kind") == MailLabel.Kind.user.rawValue && Column("isHidden") == false)
            .fetchAll(db)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let userLabels = Set(labels.map { Mailbox(labelID: $0.id, accountID: AccountID(rawValue: $0.accountID)) })

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
            // A user label counts in its own account; a system label blends every account.
            let mailbox = userLabels.contains(own) ? own : Mailbox(labelID: own.labelID)
            counts[mailbox, default: 0] += row["unread"] as Int
        }
        let allMail = threadQuery(in: .allMail)
        let allMailUnread =
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) " + allMail.sql + " AND thread.isUnread", arguments: allMail.arguments)
            ?? 0
        if allMailUnread > 0 { counts[.allMail] = allMailUnread }

        return MailboxDirectory(
            labels: labels.map { record in
                MailboxDirectory.Label(
                    mailbox: Mailbox(labelID: record.id, accountID: AccountID(rawValue: record.accountID)),
                    name: record.name, color: record.color)
            },
            unreadCounts: counts)
    }
}
