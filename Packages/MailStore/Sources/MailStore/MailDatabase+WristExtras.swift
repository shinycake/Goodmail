import Foundation
import GRDB
public import MailCore

/// What only this device knows about its mail, for a device that reads the same accounts itself, as the Apple Watch
/// does (ADR-023): which threads are pinned, asleep and muted here, which accounts the Focus lets through, and the
/// signatures kept here.
public struct DeviceMarks: Equatable, Sendable {
    public var pinned: Set<ThreadSummary.ID>
    /// Snoozed and not yet woken.
    public var asleep: Set<ThreadSummary.ID>
    /// Muted on this device, for the services that have no mute of their own.
    public var muted: Set<ThreadSummary.ID>
    public var focus: FocusFilter
    /// Each account's signature, where one is set.
    public var signatures: [AccountID: String]

    public init(
        pinned: Set<ThreadSummary.ID> = [], asleep: Set<ThreadSummary.ID> = [], muted: Set<ThreadSummary.ID> = [],
        focus: FocusFilter = .everyAccount, signatures: [AccountID: String] = [:]
    ) {
        self.pinned = pinned
        self.asleep = asleep
        self.muted = muted
        self.focus = focus
        self.signatures = signatures
    }
}

extension MailDatabase {
    /// How many threads of each kind are read, newest first: far more than a small screen lists.
    public static let deviceMarkLimit = 200

    /// This device's marks, read at once.
    public func deviceMarks() throws -> DeviceMarks {
        let limit = Self.deviceMarkLimit
        return try read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, inFocus FROM account")
            let inFocus = Set(rows.filter { $0["inFocus"] }.map { AccountID(rawValue: $0["id"]) })
            return DeviceMarks(
                pinned: try Self.threadIDs(
                    "SELECT accountID, threadID FROM pin ORDER BY rowid DESC LIMIT ?", limit: limit, in: db),
                asleep: try Self.threadIDs(
                    "SELECT accountID, threadID FROM snooze WHERE wakeAt IS NOT NULL ORDER BY wakeAt LIMIT ?",
                    limit: limit, in: db),
                muted: try Self.threadIDs(
                    "SELECT accountID, threadID FROM deviceMute ORDER BY mutedThrough DESC LIMIT ?", limit: limit,
                    in: db),
                focus: inFocus.count == rows.count ? .everyAccount : .accounts(inFocus),
                signatures: try Self.signatures(db))
        }
    }

    private static func threadIDs(_ sql: String, limit: Int, in db: Database) throws -> Set<ThreadSummary.ID> {
        Set(
            try Row.fetchAll(db, sql: sql, arguments: [limit]).map { row in
                ThreadSummary.ID(accountID: AccountID(rawValue: row["accountID"]), threadID: row["threadID"])
            })
    }
}
