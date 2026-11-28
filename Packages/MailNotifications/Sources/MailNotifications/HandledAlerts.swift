import Foundation
import MailCore
public import MailStore
import OSLog
import UserNotifications

/// Takes down delivered alerts whose mail the reader has dealt with: read, archived, moved or deleted, here, on
/// another device or in another app, as the store now has it (`MailDatabase.handledAlerts(_:)`).
public enum HandledAlerts {
    /// Removes the alerts in Notification Center whose mail no longer needs them. Off the main actor, since it reads
    /// the database. A read that fails, as while the database is suspended, leaves the alerts for the next sweep.
    @concurrent public static func dismiss(in database: MailDatabase) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        guard !delivered.isEmpty else { return }
        do {
            let accounts = try database.accounts()
            let alerts = delivered.compactMap { notification in
                DeliveredAlert(
                    identifier: notification.request.identifier, userInfo: notification.request.content.userInfo,
                    deliveredAt: notification.date, accounts: accounts)
            }
            guard !alerts.isEmpty else { return }
            let checkedAt = Date.now
            let handled = try database.handledAlerts(alerts)
            guard !handled.isEmpty else { return }
            // New-mail and rule alerts reuse their thread's identifier, so one posted since the read is about newer
            // mail than the read saw, and stays.
            let posted = Set(
                await center.deliveredNotifications().filter { $0.date >= checkedAt }.map(\.request.identifier))
            let stale = handled.filter { !posted.contains($0) }
            guard !stale.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: stale)
            Logger.handledAlerts.notice("Took down \(stale.count, privacy: .public) alerts for mail dealt with")
        } catch {
            Logger.handledAlerts.error("Couldn't check alerts against the mail: \(error, privacy: .private)")
        }
    }
}

extension Logger {
    fileprivate static let handledAlerts = Logger(subsystem: "com.idanbirman.goodmail", category: "push")
}
