public import Foundation
import GRDB
public import MailCore

extension MailDatabase: SnoozeStore {
    /// How long a woken thread stays at the top of the Inbox.
    static let wokeShownFor: TimeInterval = 24 * 3600

    public func snoozes(of threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID: SnoozeState] {
        try read { db in
            var snoozes: [ThreadSummary.ID: SnoozeState] = [:]
            for thread in threads {
                let row = try Row.fetchOne(
                    db, sql: "SELECT wakeAt, wokeAt, keeper FROM snooze WHERE accountID = ? AND threadID = ?",
                    arguments: [thread.accountID.rawValue, thread.threadID])
                if let row, let state = Self.state(row) { snoozes[thread] = state }
            }
            return snoozes
        }
    }

    public func setSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?]) throws {
        try write { db in try Self.setSnoozes(snoozes, in: db) }
    }

    static func setSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?], in db: Database) throws {
        for (thread, state) in snoozes {
            let key: StatementArguments = [thread.accountID.rawValue, thread.threadID]
            switch state {
            case nil:
                try db.execute(sql: "DELETE FROM snooze WHERE accountID = ? AND threadID = ?", arguments: key)
            case .asleep(let until, let keeper)?:
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO snooze (accountID, threadID, wakeAt, wokeAt, keeper)
                        VALUES (?, ?, ?, NULL, ?)
                        """,
                    arguments: key + [until, keeper.rawValue])
            case .woke(let at)?:
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO snooze (accountID, threadID, wakeAt, wokeAt, keeper)
                        VALUES (?, ?, NULL, ?, NULL)
                        """,
                    arguments: key + [at])
            }
        }
    }

    public func dueSnoozes(by date: Date) throws -> [ThreadSummary.ID] {
        try read { db in try Self.asleep(in: db) }.filter { $0.wakesAt <= date }.map(\.id)
    }

    public func nextWakeDate() throws -> Date? {
        try read { db in try Self.asleep(in: db) }.first?.wakesAt
    }

    /// Every asleep thread with when this device wakes it, soonest first.
    private static func asleep(in db: Database) throws -> [(id: ThreadSummary.ID, wakesAt: Date)] {
        try Row.fetchAll(db, sql: "SELECT accountID, threadID, wakeAt, keeper FROM snooze WHERE wakeAt IS NOT NULL")
            .map { row in
                let id = ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
                return (id, keeper(row).wakeTime(for: row["wakeAt"]))
            }
            .sorted { $0.wakesAt < $1.wakesAt }
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

    static func state(_ row: Row) -> SnoozeState? {
        if let until: Date = row["wakeAt"] { return .asleep(until: until, keeper: keeper(row)) }
        if let at: Date = row["wokeAt"] { return .woke(at: at) }
        return nil
    }

    /// Who answers for an asleep row's wake. Every asleep row has one since `v34-snooze-keeper`; a keeper a newer
    /// build wrote reads as another device's, so this one never alerts for it.
    fileprivate static func keeper(_ row: Row) -> SnoozeKeeper {
        (row["keeper"] as String?).flatMap(SnoozeKeeper.init(rawValue:)) ?? .otherDevice
    }
}

extension MailFollowing {
    /// Snoozed threads, in every account, soonest to wake first, each with when it wakes. Emits now and after every
    /// change.
    public func snoozedThreads() -> AsyncThrowingStream<[SnoozedThread], any Error> {
        followed.observe { db in
            let wakeTimes = try Row.fetchAll(
                db,
                sql: "SELECT accountID, threadID, wakeAt, keeper FROM snooze WHERE wakeAt IS NOT NULL ORDER BY wakeAt")
            return try wakeTimes.compactMap { row in
                let id = ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
                return try MailDatabase.thread(id, in: db).map {
                    SnoozedThread(thread: $0, wakeAt: row["wakeAt"], keeper: MailDatabase.keeper(row))
                }
            }
        }
    }

    /// Threads put back in the Inbox by their snooze, in every account, each with when it woke. Emits now and after
    /// every change.
    public func wokenThreads() -> AsyncThrowingStream<[ThreadSummary.ID: Date], any Error> {
        followed.observe { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT accountID, threadID, wokeAt FROM snooze WHERE wokeAt IS NOT NULL")
            return Dictionary(
                uniqueKeysWithValues: rows.map {
                    (
                        ThreadSummary.ID(accountID: AccountID(rawValue: $0["accountID"]), threadID: $0["threadID"]),
                        $0["wokeAt"]
                    )
                })
        }
    }
}
