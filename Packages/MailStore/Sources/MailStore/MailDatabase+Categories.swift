import Foundation
import GRDB
public import MailCore

extension MailFollowing {
    /// Unread threads in `mailbox` per category; categories with none are left out. Emits now and after every change.
    public func categoryUnreadCounts(in mailbox: Mailbox, unsorted: Set<AccountID> = [])
        -> AsyncThrowingStream<[InboxCategory: Int], any Error>
    {
        followed.observe { db in
            var counts: [InboxCategory: Int] = [:]
            for category in InboxCategory.allCases {
                let count = try MailDatabase.threadSelection(in: mailbox, category: category, unsorted: unsorted)
                    .unreadCount(in: db)
                if count > 0 { counts[category] = count }
            }
            return counts
        }
    }
}

extension MailDatabase {
    /// `threadSelection(in:)` narrowed to the threads under `category`.
    static func threadSelection(in mailbox: Mailbox, category: InboxCategory, unsorted: Set<AccountID>)
        -> ThreadSelection
    {
        var query = threadSelection(in: mailbox)
        let others = InboxCategory.allCases.filter { $0 != .primary }.map(\.labelID)
        let unsortedIDs = unsorted.map(\.rawValue).sorted()
        let unsortedList = unsortedIDs.map { _ in "?" }.joined(separator: ", ")
        if category == .primary {
            // Labelled Primary, or with no other category, or in an account that doesn't sort its Inbox.
            query.sql += """
                 AND (EXISTS (
                    SELECT 1 FROM threadLabel AS category
                    WHERE category.accountID = thread.accountID AND category.threadID = thread.id
                    AND category.labelID = ?)
                OR NOT EXISTS (
                    SELECT 1 FROM threadLabel AS category
                    WHERE category.accountID = thread.accountID AND category.threadID = thread.id
                    AND category.labelID IN (\(others.map { _ in "?" }.joined(separator: ", "))))
                """
            query.arguments += [category.labelID]
            query.arguments += StatementArguments(others)
            if !unsortedIDs.isEmpty {
                query.sql += " OR thread.accountID IN (\(unsortedList))"
                query.arguments += StatementArguments(unsortedIDs)
            }
            query.sql += ")"
        } else {
            query.sql += """
                 AND EXISTS (
                    SELECT 1 FROM threadLabel AS category
                    WHERE category.accountID = thread.accountID AND category.threadID = thread.id
                    AND category.labelID = ?)
                """
            query.arguments += [category.labelID]
            if !unsortedIDs.isEmpty {
                query.sql += " AND thread.accountID NOT IN (\(unsortedList))"
                query.arguments += StatementArguments(unsortedIDs)
            }
        }
        return query
    }
}
