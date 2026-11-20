import MailCore
import MailStore
import OSLog
import UserNotifications

/// Keeps the number on the app's icon on the unread count for the app's lifetime, as `MailDatabase.badgeCount()`
/// counts it. The notification extension sets it too, after each push it fetches for.
///
/// iOS drops a count set before the reader allowed badges, and the count only changes when mail does, so the latest
/// count is set again whenever the reader comes to the app and once they answer the permission prompt. It asks for that
/// permission itself, since every account's mail counts, push or not.
final class AppBadge {
    private let database: MailDatabase
    /// The accounts now, read when deciding whether there is anything to ask permission for.
    private var accounts: () -> [Account] = { [] }
    /// Follows the count for the app's lifetime.
    private var following: Task<Void, Never>?
    /// The latest count handed to iOS. Each waits for the one before it, so an older count never lands last.
    private var setting: Task<Void, Never>?
    /// The count last read, `nil` before the first.
    private var count: Int?
    /// The ask for permission at launch, for builds and accounts without push, which never reach the push ask.
    private var asking: Task<Void, Never>?

    init(database: MailDatabase) {
        self.database = database
    }

    func start(accounts: @escaping () -> [Account], presence: PresenceTracker) {
        self.accounts = accounts
        following = Task { [weak self, database] in
            do {
                for try await count in database.badgeCounts() { self?.set(count) }
            } catch {
                Logger.push.error("Stopped updating the badge: \(error, privacy: .public)")
            }
        }
        presence.follow { [weak self] _, new in
            if new == .attended { self?.setAgain() }
        }
        asking = Task { [weak self] in await self?.askForPermission() }
    }

    /// Asks once there is an account, whose mail can alert or at least count on the badge: asking on first launch,
    /// before the reader has added one, has nothing to explain it. Asks again, without a prompt, where alerts were
    /// allowed without badges, as on installs whose permission iOS recorded without them. Then sets the count again,
    /// since one set before the answer didn't show.
    func askForPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if Self.needsAsking(settings, hasAccounts: !accounts().isEmpty) {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                let badges = await center.notificationSettings().badgeSetting.rawValue
                Logger.push.notice(
                    "Asked for alerts and badges: granted \(granted, privacy: .public), badges \(badges, privacy: .public)"
                )
            } catch {
                Logger.push.error("Couldn't ask for alerts: \(error, privacy: .public)")
            }
        }
        setAgain()
    }

    /// Whether to ask iOS for alerts and badges: never asked with an account to explain it, or allowed without
    /// badges.
    nonisolated static func needsAsking(_ settings: UNNotificationSettings, hasAccounts: Bool) -> Bool {
        switch settings.authorizationStatus {
        case .notDetermined: hasAccounts
        case .authorized, .provisional, .ephemeral: settings.badgeSetting == .notSupported
        case .denied: false
        @unknown default: false
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
            let center = UNUserNotificationCenter.current()
            do {
                try await center.setBadgeCount(count)
                // What iOS allows, so a badge that doesn't show can be traced in Console.
                let settings = await center.notificationSettings()
                let (authorization, badges) = (settings.authorizationStatus.rawValue, settings.badgeSetting.rawValue)
                Logger.push.notice(
                    """
                    Set the badge to \(count, privacy: .public), authorization \(authorization, privacy: .public), \
                    badges \(badges, privacy: .public)
                    """)
            } catch {
                Logger.push.error("Couldn't set the badge: \(error, privacy: .public)")
            }
        }
    }
}
