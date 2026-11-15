import MailStore
import OSLog
import UIKit
import UserNotifications

/// Keeps the number on the app's icon on the unread count for the app's lifetime, as `MailDatabase.badgeCount()`
/// counts it. The notification extension sets it too, after each push it fetches for.
///
/// iOS drops a count set before the reader allowed badges, and the count only changes when mail does, so the latest
/// count is set again whenever the app comes forward and once the reader answers the permission prompt.
final class AppBadge {
    private let database: MailDatabase
    /// Follows the count for the app's lifetime.
    private var following: Task<Void, Never>?
    /// The latest count handed to iOS. Each waits for the one before it, so an older count never lands last.
    private var setting: Task<Void, Never>?
    /// The count last read, `nil` before the first.
    private var count: Int?

    init(database: MailDatabase) {
        self.database = database
    }

    func start() {
        following = Task { [weak self, database] in
            do {
                for try await count in database.badgeCounts() { self?.set(count) }
            } catch {
                Logger.push.error("Stopped updating the badge: \(error, privacy: .public)")
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAgain() }
        }
    }

    /// Sets the latest count again, as after the reader allowed badges.
    func setAgain() {
        if let count { set(count) }
    }

    private func set(_ count: Int) {
        self.count = count
        let previous = setting
        setting = Task {
            await previous?.value
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(count)
            } catch {
                Logger.push.error("Couldn't set the badge: \(error, privacy: .public)")
            }
        }
    }
}
