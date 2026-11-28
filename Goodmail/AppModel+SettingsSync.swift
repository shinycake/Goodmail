import Foundation
import MailCore
import MailStore
import MailUI
import OSLog

/// Keeping the reader's settings the same on all their devices, through iCloud Keychain (`SettingsSync`). Passes run
/// at launch, on each foreground sync round, when Settings closes and when the app leaves the foreground; each takes up what the other devices changed
/// and shares what changed here.
extension AppModel {
    /// Posted after a pass changed settings on this device, with the names of the groups that changed under
    /// `changedSettingsKey`, so the windows can show them.
    nonisolated static let settingsDidSync = Notification.Name("GoodmailSettingsDidSync")
    nonisolated static let changedSettingsKey = "changed"

    /// Shares what the reader just changed, settings and mail state, without waiting for the next round, as Settings
    /// closes or the app leaves the foreground. It runs as background work, so leaving the app straight after doesn't
    /// cut it short, and after any pass asked for before it.
    func shareSettingsNow() {
        let previous = settingsShare
        settingsShare = Task {
            await previous?.value
            await BackgroundDatabaseWork.shared.run("Sharing settings") {
                await syncSettings()
                await syncMailState()
            }
        }
    }

    /// One pass. A failure waits for the next one.
    func syncSettings() async {
        guard let settingsSync else { return }
        let pass: SettingsSyncPass
        do {
            pass = try await settingsSync.sync()
        } catch {
            Logger.settingsSync.error("Couldn't sync the settings: \(error, privacy: .public)")
            return
        }
        for failure in pass.failures {
            Logger.settingsSync.error(
                "Couldn't sync \(failure.family, privacy: .public): \(failure.error, privacy: .public)")
        }
        guard !pass.changed.isEmpty else { return }
        // Alerts turned on or off elsewhere change what this device asks the relay to wake it for.
        if pass.changed.contains(MailDatabase.SyncedGroup.alerts) { await refreshPush() }
        NotificationCenter.default.post(
            name: Self.settingsDidSync, object: self, userInfo: [Self.changedSettingsKey: pass.changed])
    }
}

extension SettingsSync {
    /// The app's settings sync: the preferences and the database's settings, shared through iCloud Keychain under
    /// their own service, with the ledger in this device's Application Support.
    @MainActor static func synced(_ database: OffMainDatabase) -> SettingsSync {
        ImageTrustRules().foldInLegacyRules()
        return SettingsSync(
            cloud: Keychain(service: "com.idanbirman.goodmail.settings", place: .iCloud),
            ledger: SettingsLedgerFile(
                url: .applicationSupportDirectory.appending(path: "SettingsSync/ledger.json")),
            families: Preferences.syncedSettings + database.syncedSettings)
    }
}

extension Logger {
    nonisolated static let settingsSync = Logger(subsystem: "com.idanbirman.goodmail", category: "settings-sync")
}
