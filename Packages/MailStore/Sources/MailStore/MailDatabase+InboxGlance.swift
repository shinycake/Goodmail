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
    static func inboxGlance(limit: Int, in db: Database) throws -> InboxGlance {
        let inbox = threadSelection(in: .inbox)
        let newest = try fetchThreads(db, query: inbox, limit: limit)
        let pinned = inbox.filtered(
            "EXISTS (SELECT 1 FROM pin WHERE pin.accountID = thread.accountID AND pin.threadID = thread.id)")
        let pinnedThreads = try fetchThreads(db, query: pinned, limit: limit)
        let newestIDs = Set(newest.map(\.id))
        let threads = (newest + pinnedThreads.filter { !newestIDs.contains($0.id) }).sorted { $0.date > $1.date }
        let unreadThreads = inbox.filtered("thread.isUnread")
        let unread = try Row.fetchAll(
            db,
            sql: "SELECT thread.accountID AS account, COUNT(*) AS count " + unreadThreads.sql
                + " GROUP BY thread.accountID",
            arguments: unreadThreads.arguments)
        return InboxGlance(
            accounts: try AccountRecord.order(Column("position"), Column("createdAt")).fetchAll(db).compactMap(
                \.account),
            threads: threads,
            pinned: Set(pinnedThreads.map(\.id)),
            unread: Dictionary(
                uniqueKeysWithValues: unread.map { (AccountID(rawValue: $0["account"]), $0["count"] as Int) }))
    }
}

extension MailFollowing {
    /// The unified Inbox's newest `limit` threads and its pinned ones, with the accounts and their unread counts.
    /// Emits now and after every change. Like the Inbox, it shows only the accounts the Focus lets through.
    public func inboxGlance(limit: Int) -> AsyncThrowingStream<InboxGlance, any Error> {
        followed.observe { db in try MailDatabase.inboxGlance(limit: limit, in: db) }
    }
}
