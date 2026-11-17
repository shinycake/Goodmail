import Foundation
import GRDB
public import MailCore

/// The unified Inbox at a glance, as a small screen such as the Apple Watch shows it.
public struct InboxGlance: Equatable, Sendable {
    /// Every account, in the reader's order.
    public var accounts: [Account]
    /// The newest Inbox threads, then any pinned Inbox thread older than those, newest first.
    public var threads: [ThreadSummary]
    /// Which of `threads` are pinned.
    public var pinned: Set<ThreadSummary.ID>
    /// Each account's unread Inbox threads, counted over the whole Inbox, not only `threads`.
    public var unread: [AccountID: Int]

    public init(
        accounts: [Account], threads: [ThreadSummary], pinned: Set<ThreadSummary.ID>, unread: [AccountID: Int]
    ) {
        self.accounts = accounts
        self.threads = threads
        self.pinned = pinned
        self.unread = unread
    }
}

extension MailDatabase {
    /// The unified Inbox's newest `limit` threads and its pinned ones, with the accounts and their unread counts.
    /// Emits now and after every change. Like the Inbox, it shows only the accounts the Focus lets through.
    public func inboxGlance(limit: Int) -> AsyncThrowingStream<InboxGlance, any Error> {
        observe { db in try Self.inboxGlance(limit: limit, in: db) }
    }

    static func inboxGlance(limit: Int, in db: Database) throws -> InboxGlance {
        let inbox = threadQuery(in: .inbox)
        let newest = try fetchThreads(db, query: inbox, limit: limit)
        let isPinned =
            " AND EXISTS (SELECT 1 FROM pin WHERE pin.accountID = thread.accountID AND pin.threadID = thread.id)"
        let pinnedThreads = try fetchThreads(db, query: (inbox.sql + isPinned, inbox.arguments), limit: limit)
        let newestIDs = Set(newest.map(\.id))
        let threads = (newest + pinnedThreads.filter { !newestIDs.contains($0.id) }).sorted { $0.date > $1.date }
        let unread = try Row.fetchAll(
            db,
            sql: "SELECT thread.accountID AS account, COUNT(*) AS count " + inbox.sql
                + " AND thread.isUnread GROUP BY thread.accountID",
            arguments: inbox.arguments)
        return InboxGlance(
            accounts: try AccountRecord.order(Column("position"), Column("createdAt")).fetchAll(db).compactMap(
                \.account),
            threads: threads,
            pinned: Set(pinnedThreads.map(\.id)),
            unread: Dictionary(
                uniqueKeysWithValues: unread.map { (AccountID(rawValue: $0["account"]), $0["count"] as Int) }))
    }
}
