import Foundation
import GRDB
import MailCore

extension MailDatabase: NotificationStore {
    public func notifications(for account: AccountID, now: Date) throws -> AccountNotifications {
        try pool.read { db in try Self.notifications(for: account, now: now, in: db) }
    }

    public func setNotificationLevel(_ level: NotificationLevel, for account: AccountID, now: Date) throws {
        try write { db in
            var settings = try Self.notifications(for: account, now: now, in: db)
            settings.level = level
            try NotificationSettingsRecord(account: account, settings).save(db)
        }
    }

    public func markSeen(through date: Date, for account: AccountID, now: Date) throws {
        try write { db in
            var settings = try Self.notifications(for: account, now: now, in: db)
            guard date > settings.seenThrough else { return }
            settings.seenThrough = date
            try NotificationSettingsRecord(account: account, settings).save(db)
        }
    }

    /// The threads among `arrived` that alert, newest first, recorded as seen in the same transaction, so two
    /// processes catching up on the same change alert for it once.
    public func claimAlerts(among arrived: [ThreadSummary], in account: Account, now: Date) throws -> [ThreadSummary] {
        try write { db in
            var settings = try Self.notifications(for: account.id, now: now, in: db)
            let (threads, seenThrough) = settings.alerts(among: arrived, in: account)
            settings.seenThrough = seenThrough
            try NotificationSettingsRecord(account: account.id, settings).save(db)
            return threads
        }
    }

    public func pushSubscription(for account: AccountID) throws -> PushSubscription? {
        try pool.read { db in try PushSubscriptionRecord.fetchOne(db, key: account.rawValue)?.subscription }
    }

    public func setPushSubscription(_ subscription: PushSubscription?, for account: AccountID) throws {
        try write { db in
            guard let subscription else {
                _ = try PushSubscriptionRecord.deleteOne(db, key: account.rawValue)
                return
            }
            try PushSubscriptionRecord(account: account, subscription).save(db)
        }
    }

    /// The newest Inbox thread stored for the account, which the reader has seen once the app showed it.
    public func newestInboxDate(for account: AccountID) throws -> Date? {
        try pool.read { db in
            try Date.fetchOne(
                db,
                sql: """
                    SELECT MAX(thread.date) FROM thread
                    JOIN threadLabel ON threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                    WHERE thread.accountID = ? AND threadLabel.labelID = ?
                    """,
                arguments: [account.rawValue, SystemLabel.inbox])
        }
    }

    /// The app badge: unread Inbox threads, counted as each account alerts: all of them, Primary only, or none.
    public func badgeCount() throws -> Int {
        try pool.read { db in try Self.badgeCount(in: db) }
    }

    /// `badgeCount()`, now and after every change.
    public func badgeCounts() -> AsyncThrowingStream<Int, any Error> {
        observe { db in try Self.badgeCount(in: db) }
    }

    static func badgeCount(in db: Database) throws -> Int {
        let levels = Dictionary(
            uniqueKeysWithValues: try NotificationSettingsRecord.fetchAll(db).map { ($0.accountID, $0.settings.level) })
        var total = 0
        for id in try String.fetchAll(db, sql: "SELECT id FROM account") {
            let inbox = Mailbox(labelID: SystemLabel.inbox, accountID: AccountID(rawValue: id))
            let query: (sql: String, arguments: StatementArguments)
            switch levels[id] ?? .all {
            case .off: continue
            case .all: query = threadQuery(in: inbox)
            case .primary: query = threadQuery(in: inbox, category: .primary, unsorted: [])
            }
            total +=
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) " + query.sql + " AND thread.isUnread", arguments: query.arguments) ?? 0
        }
        return total
    }

    private static func notifications(for account: AccountID, now: Date, in db: Database) throws
        -> AccountNotifications
    {
        try NotificationSettingsRecord.fetchOne(db, key: account.rawValue)?.settings ?? .initial(at: now)
    }
}

struct NotificationSettingsRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notificationSettings"

    var accountID: String
    var level: String
    var seenThrough: Date

    init(account: AccountID, _ settings: AccountNotifications) {
        accountID = account.rawValue
        level = settings.level.rawValue
        seenThrough = settings.seenThrough
    }

    /// A level this build doesn't know, as from a newer one, reads as All.
    var settings: AccountNotifications {
        AccountNotifications(level: NotificationLevel(rawValue: level) ?? .all, seenThrough: seenThrough)
    }
}

struct PushSubscriptionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pushSubscription"

    var accountID: String
    var deviceToken: String
    var environment: String
    /// The `PushChannel`, as JSON.
    var channel: String
    var renewedAt: Date
    var expiresAt: Date

    init(account: AccountID, _ subscription: PushSubscription) throws {
        accountID = account.rawValue
        deviceToken = subscription.device.hex
        environment = subscription.device.environment.rawValue
        channel = String(decoding: try JSONEncoder().encode(subscription.channel), as: UTF8.self)
        renewedAt = subscription.renewedAt
        expiresAt = subscription.expiresAt
    }

    /// `nil` for a row this build can't read, as from a newer one, which then subscribes again.
    var subscription: PushSubscription? {
        guard let environment = APNsEnvironment(rawValue: environment),
            let channel = try? JSONDecoder().decode(PushChannel.self, from: Data(channel.utf8))
        else { return nil }
        return PushSubscription(
            device: DeviceToken(hex: deviceToken, environment: environment), channel: channel, renewedAt: renewedAt,
            expiresAt: expiresAt)
    }
}
