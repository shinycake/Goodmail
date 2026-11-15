import MailCore
import OSLog

/// Accounts whose servers report changes as they happen (`ChangeWatchers`).
extension AppModel {
    /// Syncs an account whose server just reported a change, the way the foreground poll syncs every account: queued
    /// actions first, so the sync reads the server after them.
    func syncChanged(_ id: AccountID) async {
        do {
            let engine = try engine(for: id)
            await outboxes.flush(id)
            try await engine.sync()
            await markInboxSeen()
            await didChange?(.synced)
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
                .error("The sync after a reported change failed: \(error, privacy: .public)")
        }
    }
}
