public import Foundation
public import GRDB
public import MailCore

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
    /// processes catching up on the same change alert for it once. A reply to a thread muted on the device never
    /// alerts. An account the Focus leaves out alerts for none, and its mail still counts as seen, so it doesn't all
    /// alert once the Focus ends.
    public func claimAlerts(among arrived: [ThreadSummary], in account: Account, now: Date) throws -> [ThreadSummary] {
        try write { db in
            var settings = try Self.notifications(for: account.id, now: now, in: db)
            let audible = try arrived.filter { try !Self.isDeviceMuted($0.id, in: db) }
            let (threads, seenThrough) = settings.alerts(among: audible)
            settings.seenThrough = seenThrough
            try NotificationSettingsRecord(account: account.id, settings).save(db)
            return try Self.isInFocus(account.id, in: db) ? threads : []
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
