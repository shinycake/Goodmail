import MailNotifications
import MailStore
import OSLog

/// Takes down the alerts of mail the reader has dealt with, for the app's lifetime: whenever a thread may have been
/// read, filed or deleted (`MailDatabase.handlingChanges()`), here, in a sync of what changed on another device or in
/// another app, or in what the notification extension stored, it sweeps Notification Center (`HandledAlerts`).
final class HandledAlertsSweep {
    private let database: OffMainDatabase
    /// Follows the changes for the app's lifetime, one sweep at a time.
    private var following: Task<Void, Never>?

    init(database: OffMainDatabase) {
        self.database = database
    }

    /// Call once. The first change comes at once, so the alerts left from before launch are swept too. Each sweep
    /// reads the database off the main actor.
    func start() {
        following = Task { [database] in
            do {
                for try await _ in database.handlingChanges() { await HandledAlerts.dismiss(in: database.blocking) }
            } catch {
                Logger.push.error("Stopped taking down alerts for mail dealt with: \(error, privacy: .public)")
            }
        }
    }
}
