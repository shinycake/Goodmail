import Foundation
import GRDB
import MailCore

/// A selection of threads, `FROM … WHERE …` with the `thread` table named `thread`, and the order that lists it
/// newest first.
struct ThreadSelection {
    var sql: String
    var arguments: StatementArguments
    var order: Order

    /// Newest first; threads of the same date newest row first, a place that rewriting a thread's labels leaves alone
    /// (`replaceLabels`). The date comes from the table that drives the query,
    /// so SQLite walks an index in order instead of sorting every match before it can return the first (v39).
    enum Order {
        /// By `thread.date`: All Mail, and every selection that doesn't go through a label.
        case thread
        /// By `threadLabel.date`, the thread's date kept beside each of its labels: a label's mailbox.
        case label

        /// The table whose date and index set the order.
        var table: String {
            switch self {
            case .thread: "thread"
            case .label: "threadLabel"
            }
        }

        var sql: String { "ORDER BY \(table).date DESC, \(table).rowid DESC" }
    }

    /// The threads it selects that also meet `condition`, an SQL expression.
    func filtered(_ condition: String, _ arguments: StatementArguments = []) -> ThreadSelection {
        ThreadSelection(sql: sql + " AND " + condition, arguments: self.arguments + arguments, order: order)
    }

    /// How many of its threads are unread.
    func unreadCount(in db: Database) throws -> Int {
        let unread = filtered("thread.isUnread")
        return try Int.fetchOne(db, sql: "SELECT COUNT(*) " + unread.sql, arguments: unread.arguments) ?? 0
    }

    /// The statement that reads its threads as list rows, in order, only the first `limit` when there is one.
    func listing(limit: Int?) -> String {
        """
        SELECT thread.*,
            (SELECT group_concat(labelID, char(31)) FROM threadLabel AS all_labels
             WHERE all_labels.accountID = thread.accountID AND all_labels.threadID = thread.id) AS labelIDs
        \(sql)
        \(order.sql)
        """ + (limit.map { " LIMIT \($0)" } ?? "")
    }
}

extension MailDatabase {
    /// The threads in `mailbox`.
    static func threadSelection(in mailbox: Mailbox) -> ThreadSelection {
        var query: ThreadSelection
        if let label = mailbox.labelID {
            query = ThreadSelection(
                sql: """
                    FROM thread
                    JOIN threadLabel ON threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                    WHERE threadLabel.labelID = ?
                    """,
                arguments: [label], order: .label)
        } else {
            query = ThreadSelection(
                sql: """
                    FROM thread
                    WHERE NOT EXISTS (
                        SELECT 1 FROM threadLabel AS excluded
                        WHERE excluded.accountID = thread.accountID AND excluded.threadID = thread.id
                        AND excluded.labelID IN (?, ?))
                    """,
                arguments: [SystemLabel.spam, SystemLabel.trash], order: .thread)
        }
        if let account = mailbox.accountID {
            // On the table that sets the order, whose index then reads only the account's threads, in order.
            return query.filtered("\(query.order.table).accountID = ?", [account.rawValue])
        }
        // The unary plus keeps SQLite from reading the Focus's accounts one by one from an index, which would leave
        // their threads to sort afterwards: the Focus only filters what the ordered walk finds.
        return query.filtered("+thread.accountID IN (SELECT id FROM account WHERE inFocus)")
    }

    static func fetchThreads(_ db: Database, query: ThreadSelection, limit: Int? = nil) throws -> [ThreadSummary] {
        let rows = try Row.fetchCursor(db, sql: query.listing(limit: limit), arguments: query.arguments)
        return try Array(
            rows.map { row in
                let labels: String = row["labelIDs"] ?? ""
                return try ThreadRecord(row: row).summary(
                    labelIDs: Set(labels.split(separator: "\u{1F}").map(String.init)))
            }
        )
    }
}
