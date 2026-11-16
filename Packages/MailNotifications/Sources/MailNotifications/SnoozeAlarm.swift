public import Foundation
public import MailCore
public import UserNotifications

/// The alert a snoozed thread gives when it wakes. Snooze runs on the device, so the alert is scheduled with iOS for
/// the wake time rather than pushed: it goes off on time whether or not the app is running. It is a new-mail alert in
/// all but its text, so a tap opens the thread and its actions work the same.
public enum SnoozeAlarm {
    /// An alarm iOS holds: its thread and when it goes off.
    public struct Scheduled: Hashable, Sendable {
        public let thread: ThreadSummary.ID
        public let wakeAt: Date

        public init(thread: ThreadSummary.ID, wakeAt: Date) {
            self.thread = thread
            self.wakeAt = wakeAt
        }
    }

    /// What brings the alarms iOS holds in line with the snoozes: the ones to take back, then the ones to schedule.
    public struct Changes: Equatable, Sendable {
        public var remove: [ThreadSummary.ID]
        public var add: [SnoozedThread]

        public var isEmpty: Bool { remove.isEmpty && add.isEmpty }
    }

    /// The changes from the alarms `scheduled` to one for each thread `snoozed`, at its wake time. An alarm whose time
    /// came by `now` is left to go off, though its thread may already have woken and left the snoozes.
    public static func changes(snoozed: [SnoozedThread], scheduled: [Scheduled], now: Date) -> Changes {
        let wanted = Dictionary(snoozed.map { ($0.thread.id, $0.wakeAt) }, uniquingKeysWith: { first, _ in first })
        let held = Dictionary(scheduled.map { ($0.thread, $0.wakeAt) }, uniquingKeysWith: { first, _ in first })
        return Changes(
            remove: scheduled.filter { $0.wakeAt > now && wanted[$0.thread] != $0.wakeAt }.map(\.thread),
            add: snoozed.filter { $0.wakeAt > now && held[$0.thread.id] != $0.wakeAt })
    }

    /// The alarm for `snoozed`, from `account`, going off at its wake time in `calendar`.
    public static func request(
        for snoozed: SnoozedThread, in account: Account, calendar: Calendar = .current
    ) -> UNNotificationRequest {
        let content = NewMailAlert.content(for: snoozed.thread, in: account)
        content.body = String(
            localized: "Back from snooze: \(snoozed.thread.snippet)", table: "SnoozeAlarm", bundle: .module,
            comment: "Text of the alert when a snoozed thread wakes; the message's preview follows")
        content.userInfo[wakeAtKey] = snoozed.wakeAt.timeIntervalSince1970
        let when = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: snoozed.wakeAt)
        return UNNotificationRequest(
            identifier: identifier(for: snoozed.thread.id), content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
    }

    /// The alarm `request` is, or `nil` for any other request, such as a new-mail alert.
    public static func scheduled(in request: UNNotificationRequest) -> Scheduled? {
        let info = request.content.userInfo
        guard request.identifier.hasPrefix(prefix), let wakeAt = info[wakeAtKey] as? TimeInterval,
            let thread = NewMailAlert.thread(in: info)
        else { return nil }
        return Scheduled(thread: thread, wakeAt: Date(timeIntervalSince1970: wakeAt))
    }

    /// Apart from the thread's new-mail alert, so neither replaces the other.
    public static func identifier(for thread: ThreadSummary.ID) -> String {
        prefix + NewMailAlert.identifier(for: thread)
    }

    private static let prefix = "snooze/"
    private static let wakeAtKey = "snoozeWakeAt"
}
