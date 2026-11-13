import Foundation
import GRDB
import MailCore

extension MailDatabase: SnoozeStore {
    /// How long a woken thread stays at the top of the Inbox.
    static let wokeShownFor: TimeInterval = 24 * 3600

    public func snoozes(of threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID: SnoozeState] {
        try pool.read { db in
            var snoozes: [ThreadSummary.ID: SnoozeState] = [:]
            for thread in threads {
                let row = try Row.fetchOne(
                    db, sql: "SELECT wakeAt, wokeAt FROM snooze WHERE accountID = ? AND threadID = ?",
                    arguments: [thread.accountID.rawValue, thread.threadID])
                if let row, let state = Self.state(row) { snoozes[thread] = state }
            }
            return snoozes
        }
    }

    public func setSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?]) throws {
        try write { db in
            for (thread, state) in snoozes {
                let key: StatementArguments = [thread.accountID.rawValue, thread.threadID]
                switch state {
                case nil:
                    try db.execute(sql: "DELETE FROM snooze WHERE accountID = ? AND threadID = ?", arguments: key)
                case .asleep(let until)?:
                    try db.execute(
                        sql:
                            "INSERT OR REPLACE INTO snooze (accountID, threadID, wakeAt, wokeAt) VALUES (?, ?, ?, NULL)",
                        arguments: key + [until])
                case .woke(let at)?:
                    try db.execute(
                        sql:
                            "INSERT OR REPLACE INTO snooze (accountID, threadID, wakeAt, wokeAt) VALUES (?, ?, NULL, ?)",
                        arguments: key + [at])
                }
            }
        }
    }

    public func dueSnoozes(by date: Date) throws -> [ThreadSummary.ID] {
        try pool.read { db in
            try Row.fetchAll(
                db, sql: "SELECT accountID, threadID FROM snooze WHERE wakeAt <= ? ORDER BY wakeAt", arguments: [date]
            ).map { ThreadSummary.ID(accountID: AccountID(rawValue: $0["accountID"]), threadID: $0["threadID"]) }
        }
    }

    public func nextWakeDate() throws -> Date? {
        try pool.read { db in try Date.fetchOne(db, sql: "SELECT MIN(wakeAt) FROM snooze") }
    }

    public func pruneSnoozes(at date: Date) throws {
        try write { db in
            try db.execute(
                sql: """
                    DELETE FROM snooze
                    WHERE wokeAt < ?
                    OR (wakeAt IS NOT NULL AND EXISTS (
                        SELECT 1 FROM threadLabel
                        WHERE threadLabel.accountID = snooze.accountID AND threadLabel.threadID = snooze.threadID
                        AND threadLabel.labelID IN (?, ?, ?)))
                    """,
                arguments: [
                    date.addingTimeInterval(-Self.wokeShownFor), SystemLabel.inbox, SystemLabel.trash,
                    SystemLabel.spam,
                ])
        }
    }

    /// Snoozed threads, in every account, soonest to wake first, each with when it wakes. Emits now and after every
    /// change.
    public func snoozedThreads() -> AsyncThrowingStream<[SnoozedThread], any Error> {
        observe { db in
            let wakeTimes = try Row.fetchAll(
                db, sql: "SELECT accountID, threadID, wakeAt FROM snooze WHERE wakeAt IS NOT NULL ORDER BY wakeAt")
            return try wakeTimes.compactMap { row in
                let id = ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
                return try Self.thread(id, in: db).map { SnoozedThread(thread: $0, wakeAt: row["wakeAt"]) }
            }
        }
    }

    private static func state(_ row: Row) -> SnoozeState? {
        if let until: Date = row["wakeAt"] { return .asleep(until: until) }
        if let at: Date = row["wokeAt"] { return .woke(at: at) }
        return nil
    }
}
