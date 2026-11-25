import Foundation
import MailUI

/// The window's side of settings changed on the reader's other devices. Most are read as they're used, such as
/// the swipe actions or the undo-send wait. The preferences that shape the mail screens, such as the row layout and
/// the theme, rebuild them where the reader is, and only when what they were built with changed (D9); under Settings
/// that waits for it to close (`settingsClosed`).
extension SceneCoordinator {
    func observeSyncedSettings() {
        deviceObservers.append(
            NotificationCenter.default.addObserver(
                forName: AppModel.settingsDidSync, object: model, queue: .main
            ) { [weak self] notification in
                let changed = notification.userInfo?[AppModel.changedSettingsKey] as? Set<String> ?? []
                MainActor.assumeIsolated { self?.followSyncedSettings(changed) }
            })
    }

    private func followSyncedSettings(_ changed: Set<String>) {
        guard changed.contains(Preferences.syncedGroup), let built = uncoveredMail, !model.accounts.isEmpty else {
            return
        }
        followSettings(builtFrom: built)
    }
}
