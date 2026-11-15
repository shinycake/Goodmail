import Foundation
import GRDB
import MailCore

/// Mute for the services that have none (`MailService.mutesOnDevice`). The store keeps each muted thread in
/// `deviceMute` and shows it the way Gmail shows its own: carrying `MUTED`, with new replies kept out of the Inbox.
/// The provider only hears the rest of each change, such as the archive that Mute makes.
extension MailDatabase {
    /// Records the mute `intent` starts or ends on a thread that carried `labels`, when the account mutes on the
    /// device, and returns what its provider still has to hear: the intent without `MUTED`, or `nil` when that leaves
    /// nothing. Other accounts' intents go as they are.
    static func deviceMuting(_ intent: OutboxIntent, from labels: Set<String>, account: String, in db: Database)
        throws -> OutboxIntent?
    {
        guard try mutesOnDevice(account, in: db) else { return intent }
        let mutedAfter =
            switch intent.action.outcome(for: labels) {
            case .labeled(let after): after.contains(SystemLabel.muted)
            case .deleted: false
            }
        let key: StatementArguments = [account, intent.threadID]
        if mutedAfter, !labels.contains(SystemLabel.muted) {
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO deviceMute (accountID, threadID, mutedThrough)
                    SELECT accountID, id, date FROM thread WHERE accountID = ? AND id = ?
                    """,
                arguments: key)
        } else if !mutedAfter, labels.contains(SystemLabel.muted) {
            try db.execute(sql: "DELETE FROM deviceMute WHERE accountID = ? AND threadID = ?", arguments: key)
        }
        guard let action = intent.action.without(SystemLabel.muted) else { return nil }
        var queued = intent
        queued.action = action
        return queued
    }

    /// After a fetch rewrote these threads, shows the device-muted ones among them as muted again. One with a message
    /// newer than its mute has seen got a reply: if that put it back in the Inbox, it is taken out again here and the
    /// archive queued for the provider, in the same transaction, so the reply never shows or alerts.
    static func reapplyDeviceMutes(account: String, threadIDs: [String], in db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT deviceMute.threadID, deviceMute.mutedThrough, thread.date FROM deviceMute
                JOIN thread ON thread.accountID = deviceMute.accountID AND thread.id = deviceMute.threadID
                WHERE deviceMute.accountID = ? AND deviceMute.threadID IN (\(databaseQuestionMarks(count: threadIDs.count)))
                """,
            arguments: [account] + StatementArguments(threadIDs))
        for row in rows {
            let threadID: String = row["threadID"]
            let date: Date = row["date"]
            let mutedThrough: Date = row["mutedThrough"]
            guard
                let labels = try apply(
                    .modifyLabels(add: [SystemLabel.muted], remove: []), account: account, thread: threadID, in: db),
                date > mutedThrough
            else { continue }
            try db.execute(
                sql: "UPDATE deviceMute SET mutedThrough = ? WHERE accountID = ? AND threadID = ?",
                arguments: [date, account, threadID])
            guard labels.contains(SystemLabel.inbox) else { continue }
            let archive = OutboxIntent(threadID: threadID, action: .archive, createdAt: .now)
            _ = try apply(archive.action, account: account, thread: threadID, in: db)
            try queue(archive, account: account, in: db)
        }
    }

    /// Whether the thread is muted on the device, so a reply to it doesn't alert.
    static func isDeviceMuted(_ thread: ThreadSummary.ID, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM deviceMute WHERE accountID = ? AND threadID = ?)",
            arguments: [thread.accountID.rawValue, thread.threadID]) ?? false
    }

    private static func mutesOnDevice(_ account: String, in db: Database) throws -> Bool {
        try String.fetchOne(db, sql: "SELECT service FROM account WHERE id = ?", arguments: [account])
            .flatMap(MailService.init(rawValue:))?.mutesOnDevice ?? false
    }
}
