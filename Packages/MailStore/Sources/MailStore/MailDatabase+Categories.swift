import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// The threads in `mailbox` that fall under `category`, newest first. Every thread of an account in `unsorted`,
    /// whose Inbox isn't split, counts as Primary. Emits now and after every change.
    public func threads(in mailbox: Mailbox, category: InboxCategory, unsorted: Set<AccountID> = [])
        -> AsyncThrowingStream<[ThreadSummary], any Error>
    {
        observe { db in
            try Self.fetchThreads(db, query: Self.threadQuery(in: mailbox, category: category, unsorted: unsorted))
        }
    }

    /// Unread threads in `mailbox` per category; categories with none are left out. Emits now and after every change.
    public func categoryUnreadCounts(in mailbox: Mailbox, unsorted: Set<AccountID> = [])
        -> AsyncThrowingStream<[InboxCategory: Int], any Error>
    {
        observe { db in
            var counts: [InboxCategory: Int] = [:]
            for category in InboxCategory.allCases {
                let query = Self.threadQuery(in: mailbox, category: category, unsorted: unsorted)
                let count =
                    try Int.fetchOne(
                        db, sql: "SELECT COUNT(*) " + query.sql + " AND thread.isUnread", arguments: query.arguments)
                    ?? 0
                if count > 0 { counts[category] = count }
            }
            return counts
        }
    }

    /// `threadQuery(in:)` narrowed to the threads under `category`.
    static func threadQuery(in mailbox: Mailbox, category: InboxCategory, unsorted: Set<AccountID>)
        -> (sql: String, arguments: StatementArguments)
    {
        var (sql, arguments) = threadQuery(in: mailbox)
        let others = InboxCategory.allCases.filter { $0 != .primary }.map(\.labelID)
        let unsortedIDs = unsorted.map(\.rawValue).sorted()
        let unsortedList = unsortedIDs.map { _ in "?" }.joined(separator: ", ")
        if category == .primary {
            // Labelled Primary, or with no other category, or in an account that doesn't sort its Inbox.
            sql += """
                 AND (EXISTS (
                    SELECT 1 FROM threadLabel AS category
                    WHERE category.accountID = thread.accountID AND category.threadID = thread.id
                    AND category.labelID = ?)
                OR NOT EXISTS (
                    SELECT 1 FROM threadLabel AS category
                    WHERE category.accountID = thread.accountID AND category.threadID = thread.id
                    AND category.labelID IN (\(others.map { _ in "?" }.joined(separator: ", "))))
                """
            arguments += [category.labelID]
            arguments += StatementArguments(others)
            if !unsortedIDs.isEmpty {
                sql += " OR thread.accountID IN (\(unsortedList))"
                arguments += StatementArguments(unsortedIDs)
            }
            sql += ")"
        } else {
            sql += """
                 AND EXISTS (
                    SELECT 1 FROM threadLabel AS category
                    WHERE category.accountID = thread.accountID AND category.threadID = thread.id
                    AND category.labelID = ?)
                """
            arguments += [category.labelID]
            if !unsortedIDs.isEmpty {
                sql += " AND thread.accountID NOT IN (\(unsortedList))"
                arguments += StatementArguments(unsortedIDs)
            }
        }
        return (sql, arguments)
    }
}
