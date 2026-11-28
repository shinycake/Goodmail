import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// Every kind of mailbox the list shows, read from the 50,000-thread `Corpus`.
struct MailboxQueryPlanTests {
    struct Shape: Sendable, CustomTestStringConvertible {
        let name: String
        let mailbox: Mailbox
        var category: InboxCategory?

        var testDescription: String { name }

        var query: ThreadSelection {
            guard let category else { return MailDatabase.threadSelection(in: mailbox) }
            return MailDatabase.threadSelection(in: mailbox, category: category, unsorted: [])
        }

        /// What the mailbox holds, worked out from the threads themselves rather than the database.
        func holds(_ thread: ThreadSummary) -> Bool {
            if mailbox.accountID == nil, !Corpus.inFocus.contains(thread.id.accountID) { return false }
            guard mailbox.contains(thread) else { return false }
            return category.map { InboxCategory(of: thread) == $0 } ?? true
        }

        static let all: [Shape] = {
            let one = Corpus.accounts[0]
            return [
                Shape(name: "Inbox", mailbox: .inbox),
                Shape(name: "Inbox, one account", mailbox: Mailbox(labelID: SystemLabel.inbox, accountID: one)),
                Shape(name: "Primary", mailbox: .inbox, category: .primary),
                Shape(
                    name: "Promotions, one account", mailbox: Mailbox(labelID: SystemLabel.inbox, accountID: one),
                    category: .promotions),
                Shape(name: "Starred", mailbox: .starred),
                Shape(name: "Sparse label", mailbox: Mailbox(labelID: Corpus.sparseLabel)),
                Shape(name: "Sparse label, one account", mailbox: Mailbox(labelID: Corpus.sparseLabel, accountID: one)),
                Shape(name: "All Mail", mailbox: .allMail),
                Shape(name: "All Mail, one account", mailbox: Mailbox(labelID: nil, accountID: one)),
            ]
        }()
    }

    private let database: MailDatabase

    init() throws {
        database = try Corpus.shared.get()
    }

    @Test(arguments: Shape.all)
    func readsInOrderFromAnIndexWithoutSorting(_ shape: Shape) throws {
        let query = shape.query
        let plan = try database.read { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + query.listing(limit: 200), arguments: query.arguments)
                .map { $0["detail"] as String }
        }
        #expect(!plan.contains { $0.contains("TEMP B-TREE") }, "\(plan.joined(separator: "\n"))")
    }

    @Test(arguments: Shape.all)
    func listsEveryThreadItHoldsNewestFirstAndTheLaterOfTwoOnTheSameDateFirst(_ shape: Shape) throws {
        let listed = try database.read { db in try MailDatabase.fetchThreads(db, query: shape.query) }
        // Newer threads have lower indexes, and the two of a pair on the same date were stored in index order.
        let newestFirst = (0..<Corpus.threadCount).sorted { ($0 / 2, $1) < ($1 / 2, $0) }
        let expected = newestFirst.map(Corpus.thread).filter(shape.holds)
        #expect(listed.map(\.id) == expected.map(\.id))
    }
}
