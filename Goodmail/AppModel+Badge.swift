import MailCore
import MailStore
import MailUI
import OSLog
import UserNotifications

/// What each account counts toward the app badge, for its setting in Settings.
extension AppModel {
    func badgeChoices() -> BadgeChoices {
        BadgeChoices(
            read: { [weak self] in await self?.badgeSources() ?? [:] },
            store: { [weak self] in await self?.setBadgeSource($0, for: $1) },
            turnedOff: {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                // Allowed without badges counts as off: iOS then has no Badges switch to turn on.
                return switch settings.authorizationStatus {
                case .notDetermined: false
                case .denied: true
                default: settings.badgeSetting != .enabled
                }
            })
    }

    private func badgeSources() async -> [AccountID: BadgeSource] {
        (try? await database.offMain { try $0.badgeSources() }) ?? [:]
    }

    /// Stores the choice. The badge follows by itself, since `AppBadge` watches the count.
    private func setBadgeSource(_ source: BadgeSource, for id: AccountID) async {
        do {
            try await database.offMain { try $0.setBadgeSource(source, for: id) }
        } catch {
            Logger.push.error("Couldn't store the badge choice: \(error, privacy: .public)")
        }
    }
}
