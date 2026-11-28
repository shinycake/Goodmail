import Foundation
public import GRDB
public import MailCore

/// The number on the app's icon, and what each account counts toward it.
extension MailDatabase {
    /// Every account's badge choice, `BadgeSource.initial` for one the reader never chose for.
    public func badgeSources() throws -> [AccountID: BadgeSource] {
        try pool.read { db in try Self.badgeSources(in: db) }
    }

    public func setBadgeSource(_ source: BadgeSource, for account: AccountID) throws {
        try write { db in try BadgeSettingRecord(accountID: account.rawValue, source: source.rawValue).save(db) }
    }

    /// The app badge: each account's unread threads in what its `BadgeSource` counts. An account the Focus leaves out
    /// counts none.
    public func badgeCount() throws -> Int {
        try pool.read { db in try Self.badgeCount(in: db) }
    }

    /// `badgeCount()`, now and after every change.
    public func badgeCounts() -> AsyncThrowingStream<Int, any Error> {
        observe { db in try Self.badgeCount(in: db) }
    }

    static func badgeCount(in db: Database) throws -> Int {
        let inFocus = Set(try String.fetchAll(db, sql: "SELECT id FROM account WHERE inFocus"))
        var total = 0
        for (id, source) in try badgeSources(in: db) where inFocus.contains(id.rawValue) {
            let inbox = Mailbox(labelID: SystemLabel.inbox, accountID: id)
            let query: ThreadSelection
            switch source {
            case .off: continue
            case .inbox: query = threadSelection(in: inbox)
            case .primary: query = threadSelection(in: inbox, category: .primary, unsorted: [])
            }
            total += try query.unreadCount(in: db)
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
