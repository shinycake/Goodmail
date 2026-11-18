import Foundation
import MailCore
import Testing

@testable import MailStore

struct NotificationStoreTests {
    private let database: MailDatabase
    private let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NotificationStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    @Test func anAccountWithoutSettingsAlertsForEverythingFromAShortWhileAgo() throws {
        #expect(try database.notifications(for: account.id, now: now) == .initial(at: now))
    }

    @Test func theLevelIsKeptAndSeenOnlyMovesForward() throws {
        try database.setNotificationLevel(.primary, for: account.id, now: now)
        try database.markSeen(through: now, for: account.id, now: now)
        try database.markSeen(through: now.addingTimeInterval(-60), for: account.id, now: now)

        #expect(
            try database.notifications(for: account.id, now: now.addingTimeInterval(999))
                == AccountNotifications(level: .primary, seenThrough: now))
    }

    @Test func alertsAreClaimedOnce() throws {
        let arrived = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t"), subject: "Hi", snippet: "",
            sender: Contact(name: nil, address: "dana@example.com"), date: now, isUnread: true, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
        #expect(try database.claimAlerts(among: [arrived], in: account, now: now).map(\.id.threadID) == ["t"])
        #expect(try database.claimAlerts(among: [arrived], in: account, now: now).isEmpty)
    }

    @Test func mailAnotherSyncStoredAMomentAgoAlertsOnce() throws {
        try database.apply(StoreChanges(accountID: account.id, upserts: [Self.stored("t", ago: 60)]))

        #expect(try database.claimAlerts(among: [], in: account, now: now).map(\.id.threadID) == ["t"])
        #expect(try database.claimAlerts(among: [], in: account, now: now).isEmpty)
    }

    @Test func mailThatArrivedAndWasAlsoStoredAlertsOnce() throws {
        try database.apply(StoreChanges(accountID: account.id, upserts: [Self.stored("t", ago: 60)]))

        let alerts = try database.claimAlerts(among: [Self.stored("t", ago: 60)], in: account, now: now)
        #expect(alerts.map(\.id.threadID) == ["t"])
    }

    @Test(arguments: [
        Self.stored("old", ago: 3600), Self.stored("read", ago: 60, isUnread: false),
        Self.stored("sent", ago: 60, labels: [SystemLabel.sent]),
    ])
    func storedMailThatIsOldReadOrOutsideTheInboxStaysQuiet(thread: ThreadSummary) throws {
        try database.markSeen(through: now.addingTimeInterval(-7200), for: account.id, now: now)
        try database.apply(StoreChanges(accountID: account.id, upserts: [thread]))

        #expect(try database.claimAlerts(among: [], in: account, now: now).isEmpty)
    }

    /// A thread of the account's dated `ago` seconds before `now`.
    private static func stored(
        _ id: String, ago: TimeInterval, isUnread: Bool = true, labels: Set<String> = [SystemLabel.inbox]
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "dana@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - ago), isUnread: isUnread, messageCount: 1,
            labelIDs: labels)
    }

    @Test func aSubscriptionIsStoredReplacedAndForgotten() throws {
        let first = PushSubscription(
            device: DeviceToken(hex: "ab", environment: .sandbox), channel: .watch, renewedAt: now,
            expiresAt: now.addingTimeInterval(9))
        try database.setPushSubscription(first, for: account.id)
        #expect(try database.pushSubscription(for: account.id) == first)

        var renewed = first
        renewed.channel = .subscription(id: "s1", clientState: "secret")
        renewed.expiresAt = now.addingTimeInterval(99)
        try database.setPushSubscription(renewed, for: account.id)
        #expect(try database.pushSubscription(for: account.id) == renewed)

        try database.setPushSubscription(nil, for: account.id)
        #expect(try database.pushSubscription(for: account.id) == nil)
    }

    @Test func removingTheAccountTakesItsSettingsWithIt() throws {
        try database.setNotificationLevel(.off, for: account.id, now: now)
        try database.setPushSubscription(
            PushSubscription(
                device: DeviceToken(hex: "ab", environment: .production), channel: .watch, renewedAt: now,
                expiresAt: now),
            for: account.id)
        try database.removeAccount(account.id)
        try database.save(account)

        #expect(try database.notifications(for: account.id, now: now).level == .all)
        #expect(try database.pushSubscription(for: account.id) == nil)
    }

    @Test func theNewestInboxDateIgnoresOtherMailboxes() throws {
        func thread(_ id: String, _ seconds: TimeInterval, _ labels: Set<String>) -> ThreadSummary {
            ThreadSummary(
                id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: id, snippet: "",
                sender: Contact(name: nil, address: "x@example.com"), date: now.addingTimeInterval(seconds),
                isUnread: true, messageCount: 1, labelIDs: labels)
        }
        try database.apply(
            StoreChanges(
                accountID: account.id,
                upserts: [thread("in", -60, [SystemLabel.inbox]), thread("sent", 0, [SystemLabel.sent])]))
        #expect(try database.newestInboxDate(for: account.id) == now.addingTimeInterval(-60))
    }
}
