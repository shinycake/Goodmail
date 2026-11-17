import Foundation
import Testing

@testable import MailCore

struct AccountNotificationsTests {
    private let account = Account(id: .generate(), email: "me@example.com", color: .blue, service: .gmail)
    private let seen = Date(timeIntervalSince1970: 1_000_000)

    private func thread(
        _ id: String, minutesAfter minutes: Double, labels: Set<String> = [SystemLabel.inbox],
        unread: Bool = true, from sender: String = "dana@example.com"
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: sender), date: seen.addingTimeInterval(minutes * 60),
            isUnread: unread, messageCount: 1, labelIDs: labels)
    }

    @Test func newUnreadInboxMailAlertsNewestFirst() {
        let notifications = AccountNotifications(level: .all, seenThrough: seen)
        let arrived = [thread("older", minutesAfter: 1), thread("newer", minutesAfter: 2)]
        let (threads, seenThrough) = notifications.alerts(among: arrived)
        #expect(threads.map(\.id.threadID) == ["newer", "older"])
        #expect(seenThrough == seen.addingTimeInterval(120))
    }

    @Test func mailAlreadySeenReadOrOutsideTheInboxDoesNotAlert() {
        let notifications = AccountNotifications(level: .all, seenThrough: seen)
        let arrived = [
            thread("seen", minutesAfter: 0),
            thread("read", minutesAfter: 1, unread: false),
            thread("archived", minutesAfter: 1, labels: []),
        ]
        #expect(notifications.alerts(among: arrived).threads.isEmpty)
    }

    /// Apple Mail alerts for a message the account sent itself once it lands unread in the Inbox, and so does the app.
    @Test func unreadInboxMailFromMeAlerts() {
        let notifications = AccountNotifications(level: .all, seenThrough: seen)
        let arrived = [thread("mine", minutesAfter: 1, from: "ME@example.com")]
        #expect(notifications.alerts(among: arrived).threads.map(\.id.threadID) == ["mine"])
    }

    @Test func aReadInboxThreadStillMovesWhatHasBeenConsidered() {
        let notifications = AccountNotifications(level: .all, seenThrough: seen)
        let (_, seenThrough) = notifications.alerts(
            among: [thread("read", minutesAfter: 5, unread: false)])
        #expect(seenThrough == seen.addingTimeInterval(300))
    }

    @Test func primaryLeavesOutTheOtherCategories() {
        let notifications = AccountNotifications(level: .primary, seenThrough: seen)
        let arrived = [
            thread("personal", minutesAfter: 1, labels: [SystemLabel.inbox, "CATEGORY_PERSONAL"]),
            thread("uncategorized", minutesAfter: 1),
            thread("promo", minutesAfter: 1, labels: [SystemLabel.inbox, "CATEGORY_PROMOTIONS"]),
        ]
        #expect(
            Set(notifications.alerts(among: arrived).threads.map(\.id.threadID))
                == ["personal", "uncategorized"])
    }

    @Test func offAlertsForNothingButStillConsidersTheMail() {
        let notifications = AccountNotifications(level: .off, seenThrough: seen)
        let (threads, seenThrough) = notifications.alerts(among: [thread("new", minutesAfter: 1)])
        #expect(threads.isEmpty)
        #expect(seenThrough == seen.addingTimeInterval(60))
    }

    @Test func aFirstAlertReachesBackAShortWhile() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let initial = AccountNotifications.initial(at: now)
        #expect(initial.level == .all)
        #expect(initial.seenThrough == now.addingTimeInterval(-AccountNotifications.firstLookback))
    }
}
