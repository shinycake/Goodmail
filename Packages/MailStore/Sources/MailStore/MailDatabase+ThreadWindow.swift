import Foundation
import GRDB
public import MailCore

/// A mailbox's list, read a window at a time (ADR-046): its newest threads, and the pinned and woken ones below them,
/// which the list leads with.
extension MailFollowing {
    /// The threads of `mailbox` in `window`, newest first. Emits now and after every change to what it lists, so a
    /// write to a thread below the window doesn't emit.
    public func threads(in mailbox: Mailbox, window: ThreadWindow) -> AsyncThrowingStream<ThreadListing, any Error> {
        let selection = MailDatabase.threadSelection(in: mailbox)
        // Signals from other processes re-run the query even when nothing it reads changed.
        return followed.observe { db in try MailDatabase.listing(of: selection, in: window, db) }
    }

    /// The threads of `mailbox` under `category` in `window`, newest first. Every thread of an account in `unsorted`,
    /// whose Inbox isn't split, counts as Primary. Emits now and after every change to what it lists.
    public func threads(
        in mailbox: Mailbox, category: InboxCategory, unsorted: Set<AccountID> = [], window: ThreadWindow
    ) -> AsyncThrowingStream<ThreadListing, any Error> {
        let selection = MailDatabase.threadSelection(in: mailbox, category: category, unsorted: unsorted)
        return followed.observe { db in try MailDatabase.listing(of: selection, in: window, db) }
    }
}

extension MailDatabase {
    /// What `selection` lists in `window`. One more than the window is read, to tell whether the mailbox goes on below
    /// it; that thread isn't listed, so a change to it alone changes nothing here.
    static func listing(of selection: ThreadSelection, in window: ThreadWindow, _ db: Database) throws
        -> ThreadListing
    {
        guard let limit = window.limit else {
            return ThreadListing(whole: try fetchThreads(db, query: selection))
        }
        var threads = try fetchThreads(db, query: selection, limit: limit + 1)
        guard threads.count > limit else { return ThreadListing(threads: threads, reach: .whole) }
        threads.removeLast()
        let listed = Set(threads.map(\.id))
        let heldSelection = held(in: selection)
        let held = try fetchThreads(db, sql: heldSelection.sortedListing, arguments: heldSelection.arguments)
            .filter { !listed.contains($0.id) }
        return ThreadListing(threads: threads, held: held, reach: .more)
    }

    /// The pinned threads of `selection`, and those back from snooze. Found from the pins and snoozes, a few rows,
    /// then looked up by key, rather than by walking the mailbox's order to test each of its threads. The union sits
    /// in a subquery of its own: SQLite looks a row value up by key only from a plain one.
    static func held(in selection: ThreadSelection) -> ThreadSelection {
        selection.filtered(
            """
            (thread.accountID, thread.id) IN (
                SELECT accountID, threadID FROM (
                    SELECT accountID, threadID FROM pin
                    UNION SELECT accountID, threadID FROM snooze WHERE wokeAt IS NOT NULL))
            """)
    }
}
