public import Foundation
import GRDB
public import MailCore

/// The mail state the reader's devices share (ADR-037), as the database reads and takes it up. What another device
/// changed is taken up on this device alone: nothing goes to the outbox, since the device that made the change
/// queued what the service has to hear, and a second copy of it is what this sharing exists to avoid.
extension MailDatabase {
    /// The pinned threads, in every account.
    public func pinnedThreadIDs() throws -> Set<ThreadSummary.ID> {
        try pool.read { db in try Self.threadIDs(in: "pin", db) }
    }

    /// Every thread's snooze, asleep or woken, in every account.
    public func allSnoozes() throws -> [ThreadSummary.ID: SnoozeState] {
        try pool.read { db in
            var snoozes: [ThreadSummary.ID: SnoozeState] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT accountID, threadID, wakeAt, wokeAt, keeper FROM snooze") {
                let id = ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
                snoozes[id] = Self.state(row)
            }
            return snoozes
        }
    }

    /// The threads muted on the device, in every account.
    public func deviceMutedThreadIDs() throws -> Set<ThreadSummary.ID> {
        try pool.read { db in try Self.threadIDs(in: "deviceMute", db) }
    }

    /// Takes up snoozes another device made, changed or ended. A thread put to sleep there leaves this device's
    /// Inbox at once, as it did there, so the snooze isn't taken for a thread put back in the Inbox some other way
    /// before this device's sync hears of the archive (`pruneSnoozes`).
    public func takeUpSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?]) throws {
        try write { db in
            try Self.setSnoozes(snoozes, in: db)
            for case (let id, .asleep?) in snoozes {
                _ = try Self.apply(.archive, account: id.accountID.rawValue, thread: id.threadID, in: db)
            }
        }
    }

    /// Takes up mutes another device made, `true`, or ended, `false`. A thread muted there shows muted here, and a
    /// reply newer than the thread as this device has it now stays out of the Inbox and doesn't alert.
    public func takeUpMutes(_ mutes: [ThreadSummary.ID: Bool], now: Date) throws {
        try write { db in
            for (id, muted) in mutes {
                let (account, thread) = (id.accountID.rawValue, id.threadID)
                if muted {
                    let date = try Date.fetchOne(
                        db, sql: "SELECT date FROM thread WHERE accountID = ? AND id = ?", arguments: [account, thread])
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO deviceMute (accountID, threadID, mutedThrough) VALUES (?, ?, ?)",
                        arguments: [account, thread, date ?? now])
                    _ = try Self.apply(
                        .modifyLabels(add: [SystemLabel.muted], remove: []), account: account, thread: thread, in: db)
                } else {
                    try db.execute(
                        sql: "DELETE FROM deviceMute WHERE accountID = ? AND threadID = ?",
                        arguments: [account, thread])
                    _ = try Self.apply(
                        .modifyLabels(add: [], remove: [SystemLabel.muted]), account: account, thread: thread, in: db)
                }
            }
        }
    }

    private static func threadIDs(in table: String, _ db: Database) throws -> Set<ThreadSummary.ID> {
        Set(
            try Row.fetchAll(db, sql: "SELECT accountID, threadID FROM \(table)").map {
                ThreadSummary.ID(accountID: AccountID(rawValue: $0["accountID"]), threadID: $0["threadID"])
            })
    }
}
