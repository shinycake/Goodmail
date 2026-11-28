import Foundation
import GRDB
public import MailCore

extension MailDatabase: PinStore {
    public func pins(among threads: [ThreadSummary.ID]) throws -> Set<ThreadSummary.ID> {
        try read { db in
            try Set(
                threads.filter { thread in
                    try Bool.fetchOne(
                        db, sql: "SELECT EXISTS (SELECT 1 FROM pin WHERE accountID = ? AND threadID = ?)",
                        arguments: [thread.accountID.rawValue, thread.threadID]) ?? false
                })
        }
    }

    public func setPins(_ pins: [ThreadSummary.ID: Bool]) throws {
        try write { db in
            for (thread, pinned) in pins {
                try db.execute(
                    sql: pinned
                        ? "INSERT OR IGNORE INTO pin (accountID, threadID) VALUES (?, ?)"
                        : "DELETE FROM pin WHERE accountID = ? AND threadID = ?",
                    arguments: [thread.accountID.rawValue, thread.threadID])
            }
        }
    }
}

extension MailFollowing {
    /// The pinned threads, in every account. Emits now and after every change.
    public func pinnedThreads() -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error> {
        followed.observe { db in
            Set(
                try Row.fetchAll(db, sql: "SELECT accountID, threadID FROM pin").map {
                    ThreadSummary.ID(accountID: AccountID(rawValue: $0["accountID"]), threadID: $0["threadID"])
                })
        }
    }
}
