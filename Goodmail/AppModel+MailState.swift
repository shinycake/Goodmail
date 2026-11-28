import Foundation
import MailCore
import MailStore
import OSLog

/// Keeping pins, snoozes and device mutes the same on all the reader's devices, through iCloud Keychain (ADR-037).
/// A pass runs before every wake of snoozed threads and again after a wake here, as the relay's quiet push syncs an
/// account, and as the app leaves the foreground. Each takes up what the other devices changed and shares what
/// changed here. The database is observed, so the lists, the alarms and the badge follow by themselves.
extension AppModel {
    /// One pass. A failure waits for the next one.
    func syncMailState() async {
        guard let mailStateSync else { return }
        do {
            let pass = try await mailStateSync.sync()
            for failure in pass.failures {
                Logger.settingsSync.error(
                    "Couldn't sync \(failure.family, privacy: .public): \(failure.error, privacy: .public)")
            }
        } catch {
            Logger.settingsSync.error("Couldn't sync the mail state: \(error, privacy: .private)")
        }
    }
}

extension SettingsSync {
    /// The database's mail state, shared through iCloud Keychain beside the settings, with a ledger of its own in this
    /// device's Application Support.
    static func mailState(_ database: OffMainDatabase) -> SettingsSync {
        SettingsSync(
            cloud: Keychain(service: "com.idanbirman.goodmail.mailstate", place: .iCloud),
            ledger: SettingsLedgerFile(
                url: .applicationSupportDirectory.appending(path: "SettingsSync/mail-state-ledger.json")),
            families: database.syncedMailState)
    }
}
