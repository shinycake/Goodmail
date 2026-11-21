import MailCore
import MailUI
import OSLog

/// Accounts whose servers report changes as they happen (`ChangeWatchers`).
extension AppModel {
    /// Syncs an account whose server just reported a change, the way the foreground poll syncs every account: queued
    /// actions first, so the sync reads the server after them.
    /// It tells `health` how it went, as every sync does, and returns whether it went through. A change the reader
    /// isn't looking at, such as one a background push reports, leaves the Inbox's seen mark alone
    /// (`markingInboxSeen`), so new mail the sync stores still alerts.
    @discardableResult
    func syncChanged(_ id: AccountID, markingInboxSeen: Bool = true) async -> Bool {
        health.syncStarted()
        defer { health.syncEnded() }
        let outcome = await Result {
            let engine = try engine(for: id)
            await outboxes.flush(id)
            try await engine.sync()
        }
        health.record(outcome, for: id)
        switch outcome {
        case .success:
            await runRules(for: accounts.filter { $0.id == id })
            if markingInboxSeen { await markInboxSeen() }
            await didChange?(.synced)
            return true
        case .failure(let error):
            Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
                .error("The sync after a reported change failed: \(error, privacy: .public)")
            return false
        }
    }
}
