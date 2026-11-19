import Foundation
import MailWrist
import UserNotifications

/// The actions on an alert the relay sends the watch itself (ADR-023): Reply, Mark as Read, Archive and Trash, as on
/// the iPhone's alerts. The relay names the category only when the alert names its conversation; the watch runs an
/// action only for an account it reads itself, since a relayed account's change needs the iPhone, which didn't answer.
extension OwnAlerts {
    /// The category the relay names, the same as the iPhone's (NewMailAlert.categoryID).
    nonisolated static let categoryID = "newMail"

    /// Makes the actions known, before launch finishes so that an action that launched the app finds them.
    static func registerActions() {
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Reply and Mark as Read first, as the most common; Trash last, as destructive.
    private static var category: UNNotificationCategory {
        let reply = UNTextInputNotificationAction(
            identifier: WristAlertAction.reply.rawValue,
            title: String(localized: "Reply", comment: "Alert action that replies to the mail"), options: [],
            icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
            textInputButtonTitle: String(localized: "Send", comment: "Sends the reply typed in an alert"),
            textInputPlaceholder: "")
        let markRead = UNNotificationAction(
            identifier: WristAlertAction.markRead.rawValue,
            title: String(localized: "Mark as Read", comment: "Alert action that marks mail read"),
            icon: UNNotificationActionIcon(systemImageName: "envelope.open"))
        let archive = UNNotificationAction(
            identifier: WristAlertAction.archive.rawValue,
            title: String(localized: "Archive", comment: "Alert action that archives the mail"),
            icon: UNNotificationActionIcon(systemImageName: "archivebox"))
        let trash = UNNotificationAction(
            identifier: WristAlertAction.trash.rawValue,
            title: String(localized: "Trash", comment: "Alert action that moves the mail to Trash"),
            options: [.destructive], icon: UNNotificationActionIcon(systemImageName: "trash"))
        return UNNotificationCategory(
            identifier: categoryID, actions: [reply, markRead, archive, trash], intentIdentifiers: [], options: [])
    }
}

extension WatchAppDelegate {
    /// Runs `action`, picked on `alert`, with the words of a reply, through the watch's own host. The restored
    /// mailbox says the accounts and their sources, also when the app was launched for the action.
    func act(_ action: WristAlertAction, on alert: TappedAlert, text: String?) async {
        let inbox = await restoredInbox()
        let mailbox = inbox.mailbox
        let target = WristAlertTarget(
            payload: alert.payload, accounts: mailbox.snapshot?.accounts ?? [], sources: mailbox.sources)
        guard let command = action.command(on: target, text: text, sources: mailbox.sources, now: .now) else {
            return
        }
        do {
            try await own.perform(command, following: mailbox)
        } catch {
            OwnAlerts.log.error("Couldn't run an alert's action on the watch: \(error, privacy: .public)")
            // A reply that didn't go shows in the app to send again, rather than being lost.
            inbox.couldntRun(command)
        }
    }
}
