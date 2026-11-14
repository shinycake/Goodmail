import Foundation
import MailCore
import UserNotifications

/// How a new-mail alert looks, and how a tap or action on one names its thread.
public enum NewMailAlert {
    public static let categoryID = "newMail"

    /// What the reader can do from an alert without opening the app.
    public enum Action: String, CaseIterable, Sendable {
        case reply, markRead, archive, trash
    }

    /// The alert for `thread`. Alerts stack by account, so each account's mail stays together however many
    /// accounts there are.
    public static func content(for thread: ThreadSummary, in account: Account) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = thread.sender.displayName
        content.subtitle =
            thread.subject.isEmpty
            ? String(localized: "No Subject", bundle: .module, comment: "Alert subtitle for mail without a subject")
            : thread.subject
        content.body = thread.snippet
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = account.id.rawValue
        content.targetContentIdentifier = identifier(for: thread.id)
        // Lets a Focus filter that names accounts let through only theirs.
        content.filterCriteria = account.id.rawValue
        content.userInfo = [accountKey: thread.id.accountID.rawValue, threadKey: thread.id.threadID]
        return content
    }

    /// The thread an alert is about, or `nil` for one that isn't a new-mail alert, such as the bare push shown
    /// when the extension couldn't fetch.
    public static func thread(in userInfo: [AnyHashable: Any]) -> ThreadSummary.ID? {
        guard let account = userInfo[accountKey] as? String, let thread = userInfo[threadKey] as? String else {
            return nil
        }
        return ThreadSummary.ID(accountID: AccountID(rawValue: account), threadID: thread)
    }

    /// The alert actions: Reply and Mark as Read first, as the most common; Trash last, as destructive.
    public static var category: UNNotificationCategory {
        let reply = UNTextInputNotificationAction(
            identifier: Action.reply.rawValue,
            title: String(localized: "Reply", bundle: .module, comment: "Alert action that replies to the mail"),
            options: [], icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
            textInputButtonTitle: String(
                localized: "Send", bundle: .module, comment: "Sends the reply typed in an alert"),
            textInputPlaceholder: "")
        let markRead = UNNotificationAction(
            identifier: Action.markRead.rawValue,
            title: String(localized: "Mark as Read", bundle: .module, comment: "Alert action that marks mail read"),
            icon: UNNotificationActionIcon(systemImageName: "envelope.open"))
        let archive = UNNotificationAction(
            identifier: Action.archive.rawValue,
            title: String(localized: "Archive", bundle: .module, comment: "Alert action that archives the mail"),
            icon: UNNotificationActionIcon(systemImageName: "archivebox"))
        let trash = UNNotificationAction(
            identifier: Action.trash.rawValue,
            title: String(localized: "Trash", bundle: .module, comment: "Alert action that moves the mail to Trash"),
            options: [.destructive], icon: UNNotificationActionIcon(systemImageName: "trash"))
        return UNNotificationCategory(
            identifier: categoryID, actions: [reply, markRead, archive, trash], intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(
                localized: "New Mail", bundle: .module, comment: "Alert text when previews are hidden"),
            categorySummaryFormat: String(
                localized: "%u more from %@", bundle: .module,
                comment: "Summary of stacked alerts: the count, then the account's address"),
            options: [])
    }

    /// The identifier of the thread's alert, so a later alert for the same thread replaces it.
    public static func identifier(for thread: ThreadSummary.ID) -> String {
        "\(thread.accountID.rawValue)/\(thread.threadID)"
    }

    private static let accountKey = "accountID"
    private static let threadKey = "threadID"
}
