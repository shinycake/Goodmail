import Foundation
import MailCore
import Testing
import UserNotifications

@testable import MailNotifications

struct SnoozeAlarmTests {
    private let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snoozed(_ id: String, hours: Double) -> SnoozedThread {
        SnoozedThread(
            thread: ThreadSummary(
                id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Lunch?",
                snippet: "Tomorrow at one", sender: Contact(name: "Dana Levi", address: "dana@example.com"),
                date: now, isUnread: false, messageCount: 1, labelIDs: []),
            wakeAt: now.addingTimeInterval(hours * 3600))
    }

    private func scheduled(_ thread: SnoozedThread) -> SnoozeAlarm.Scheduled {
        SnoozeAlarm.Scheduled(thread: thread.thread.id, wakeAt: thread.wakeAt)
    }

    @Test func aNewSnoozeIsScheduledAndOneAlreadyHeldIsLeftAlone() {
        let held = snoozed("t1", hours: 2)
        let new = snoozed("t2", hours: 5)
        let changes = SnoozeAlarm.changes(snoozed: [held, new], scheduled: [scheduled(held)], now: now)
        #expect(changes == SnoozeAlarm.Changes(remove: [], add: [new]))
    }

    @Test func aSnoozeMovedToAnotherTimeIsRescheduled() {
        let before = snoozed("t1", hours: 2)
        let after = snoozed("t1", hours: 24)
        let changes = SnoozeAlarm.changes(snoozed: [after], scheduled: [scheduled(before)], now: now)
        #expect(changes == SnoozeAlarm.Changes(remove: [before.thread.id], add: [after]))
    }

    @Test func anUnsnoozedThreadsAlarmIsTakenBack() {
        let gone = snoozed("t1", hours: 2)
        let changes = SnoozeAlarm.changes(snoozed: [], scheduled: [scheduled(gone)], now: now)
        #expect(changes == SnoozeAlarm.Changes(remove: [gone.thread.id], add: []))
    }

    @Test func anAlarmWhoseTimeCameIsLeftToGoOff() {
        let due = snoozed("t1", hours: -0.01)
        #expect(SnoozeAlarm.changes(snoozed: [], scheduled: [scheduled(due)], now: now).isEmpty, "it woke already")
        #expect(SnoozeAlarm.changes(snoozed: [due], scheduled: [], now: now).isEmpty, "no alarm for the past")
    }

    @Test func theAlarmIsTheThreadsAlertSayingItsBackAtItsWakeTime() throws {
        let thread = snoozed("t1", hours: 3)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Jerusalem"))
        let request = SnoozeAlarm.request(for: thread, in: account, calendar: calendar)

        #expect(request.content.title == "Dana Levi")
        #expect(request.content.body == "Back from snooze: Tomorrow at one")
        #expect(request.content.categoryIdentifier == NewMailAlert.categoryID)
        #expect(NewMailAlert.thread(in: request.content.userInfo) == thread.thread.id, "a tap opens the thread")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(calendar.date(from: trigger.dateComponents) == thread.wakeAt)
        #expect(!trigger.repeats)
        #expect(SnoozeAlarm.scheduled(in: request) == scheduled(thread))
        #expect(request.identifier != NewMailAlert.identifier(for: thread.thread.id))
    }

    @Test func aNewMailAlertIsNoAlarm() {
        let alert = UNNotificationRequest(
            identifier: NewMailAlert.identifier(for: snoozed("t1", hours: 1).thread.id),
            content: NewMailAlert.content(for: snoozed("t1", hours: 1).thread, in: account), trigger: nil)
        #expect(SnoozeAlarm.scheduled(in: alert) == nil)
    }
}
