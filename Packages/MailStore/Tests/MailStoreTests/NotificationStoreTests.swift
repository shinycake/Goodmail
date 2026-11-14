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

    @Test func theBadgeCountsUnreadInboxMailAsEachAccountAlerts() throws {
        func thread(_ id: String, unread: Bool = true, labels: Set<String> = [SystemLabel.inbox]) -> ThreadSummary {
            ThreadSummary(
                id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "", snippet: "",
                sender: Contact(name: nil, address: "dana@example.com"), date: now, isUnread: unread, messageCount: 1,
                labelIDs: labels)
        }
        try database.upsert([
            thread("primary"), thread("promo", labels: [SystemLabel.inbox, InboxCategory.promotions.labelID]),
            thread("read", unread: false), thread("archived", labels: []),
        ])
        #expect(try database.badgeCount() == 2)
        try database.setNotificationLevel(.primary, for: account.id, now: now)
        #expect(try database.badgeCount() == 1)
        try database.setNotificationLevel(.off, for: account.id, now: now)
        #expect(try database.badgeCount() == 0)
    }

    @Test func aSubscriptionIsStoredReplacedAndForgotten() throws {
        let first = PushSubscription(deviceToken: "ab", registeredAt: now, watchExpiresAt: now.addingTimeInterval(9))
        try database.setPushSubscription(first, for: account.id)
        #expect(try database.pushSubscription(for: account.id) == first)

        var renewed = first
        renewed.watchExpiresAt = now.addingTimeInterval(99)
        try database.setPushSubscription(renewed, for: account.id)
        #expect(try database.pushSubscription(for: account.id) == renewed)

        try database.setPushSubscription(nil, for: account.id)
        #expect(try database.pushSubscription(for: account.id) == nil)
    }

    @Test func removingTheAccountTakesItsSettingsWithIt() throws {
        try database.setNotificationLevel(.off, for: account.id, now: now)
        try database.setPushSubscription(
            PushSubscription(deviceToken: "ab", registeredAt: now, watchExpiresAt: now), for: account.id)
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
