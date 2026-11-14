import MailCore
import MailNotifications
import MailStore
import OSLog
import UserNotifications

/// Keeps an alarm scheduled with iOS for each snoozed thread, so it alerts when it wakes. It follows the stored
/// snoozes rather than each command, so snoozing, unsnoozing, undo, and threads that leave Snoozed some other way all
/// land the same way.
final class SnoozeAlarms {
    private let model: AppModel
    /// Follows the snoozes for the app's lifetime.
    private var following: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        following = Task { [model] in
            do {
                for try await snoozed in model.database.snoozedThreads() {
                    await Self.schedule(snoozed, accounts: model.accounts)
                }
            } catch {
                Logger.snooze.error("Stopped scheduling snooze alerts: \(error, privacy: .public)")
            }
        }
    }

    /// Brings iOS's alarms in line with `snoozed`. Asks for alerts first if they haven't been asked about, since a
    /// snooze is the reader asking to be reminded.
    @concurrent private static func schedule(_ snoozed: [SnoozedThread], accounts: [Account]) async {
        let center = UNUserNotificationCenter.current()
        let scheduled = await center.pendingNotificationRequests().compactMap(SnoozeAlarm.scheduled)
        let changes = SnoozeAlarm.changes(snoozed: snoozed, scheduled: scheduled, now: .now)
        guard !changes.isEmpty else { return }
        if !changes.add.isEmpty, await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        center.removePendingNotificationRequests(withIdentifiers: changes.remove.map(SnoozeAlarm.identifier))
        for thread in changes.add {
            guard let account = accounts.first(where: { $0.id == thread.thread.id.accountID }) else { continue }
            do {
                try await center.add(SnoozeAlarm.request(for: thread, in: account))
            } catch {
                Logger.snooze.error("Couldn't schedule a snooze alert: \(error, privacy: .public)")
            }
        }
    }
}

extension Logger {
    nonisolated static let snooze = Logger(subsystem: "com.idanbirman.goodmail", category: "snooze")
}
