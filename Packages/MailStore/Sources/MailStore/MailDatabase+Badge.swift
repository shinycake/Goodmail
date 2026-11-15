import Foundation
import GRDB
import MailCore

/// The number on the app's icon, and what each account counts toward it.
extension MailDatabase {
    /// Every account's badge choice, `BadgeSource.initial` for one the reader never chose for.
    public func badgeSources() throws -> [AccountID: BadgeSource] {
        try pool.read { db in try Self.badgeSources(in: db) }
    }

    public func setBadgeSource(_ source: BadgeSource, for account: AccountID) throws {
        try write { db in try BadgeSettingRecord(accountID: account.rawValue, source: source.rawValue).save(db) }
    }

    /// The app badge: each account's unread threads in what its `BadgeSource` counts.
    public func badgeCount() throws -> Int {
        try pool.read { db in try Self.badgeCount(in: db) }
    }

    /// `badgeCount()`, now and after every change.
    public func badgeCounts() -> AsyncThrowingStream<Int, any Error> {
        observe { db in try Self.badgeCount(in: db) }
    }

    static func badgeCount(in db: Database) throws -> Int {
        var total = 0
        for (id, source) in try badgeSources(in: db) {
            let inbox = Mailbox(labelID: SystemLabel.inbox, accountID: id)
            let query: (sql: String, arguments: StatementArguments)
            switch source {
            case .off: continue
            case .inbox: query = threadQuery(in: inbox)
            case .primary: query = threadQuery(in: inbox, category: .primary, unsorted: [])
            }
            total +=
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) " + query.sql + " AND thread.isUnread", arguments: query.arguments) ?? 0
        }
        return total
    }

    private static func badgeSources(in db: Database) throws -> [AccountID: BadgeSource] {
        let chosen = Dictionary(
            uniqueKeysWithValues: try BadgeSettingRecord.fetchAll(db).map { ($0.accountID, $0.badgeSource) })
        return Dictionary(
            uniqueKeysWithValues: try String.fetchAll(db, sql: "SELECT id FROM account").map { id in
                (AccountID(rawValue: id), chosen[id] ?? .initial)
            })
    }
}

struct BadgeSettingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "badgeSettings"

    var accountID: String
    var source: String

    /// A source this build doesn't know, as from a newer one, counts the Inbox.
    var badgeSource: BadgeSource { BadgeSource(rawValue: source) ?? .initial }
}
