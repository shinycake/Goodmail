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
                return settings.authorizationStatus == .denied || settings.badgeSetting == .disabled
            })
    }

    private func badgeSources() async -> [AccountID: BadgeSource] {
        let database = database
        return (try? await Self.offMain { try database.badgeSources() }) ?? [:]
    }

    /// Stores the choice. The badge follows by itself, since `AppBadge` watches the count.
    private func setBadgeSource(_ source: BadgeSource, for id: AccountID) async {
        let database = database
        do {
            try await Self.offMain { try database.setBadgeSource(source, for: id) }
        } catch {
            Logger.push.error("Couldn't store the badge choice: \(error, privacy: .public)")
        }
    }
}
