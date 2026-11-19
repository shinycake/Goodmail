import Foundation
public import MailCore
public import UserNotifications

/// The notification a rule asks for (`RuleAction.notify`): its keyword as the title, so a Shortcuts automation on
/// Goodmail's notifications that watches for the keyword runs on it. It names its message's thread, so a tap opens it
/// and the new-mail actions work on it.
public enum RuleNotification {
    /// Where rule notifications stack, apart from each account's new mail.
    static let threadIdentifier = "rules"

    public static func request(for alert: RuleAlert, in account: Account) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.keyword
        content.subtitle = alert.sender.displayName
        content.body =
            alert.subject.isEmpty
            ? String(localized: "No Subject", bundle: .module, comment: "Alert subtitle for mail without a subject")
            : alert.subject
        content.sound = .default
        content.categoryIdentifier = NewMailAlert.categoryID
        content.threadIdentifier = threadIdentifier
        content.targetContentIdentifier = NewMailAlert.identifier(for: alert.thread)
        content.filterCriteria = account.id.rawValue
        content.userInfo = AlertedThread.userInfo(for: alert.thread)
        // One per rule and thread: the same rule matching a later reply replaces it.
        return UNNotificationRequest(
            identifier: "\(DeliveredAlert.rulePrefix)\(alert.rule)/\(NewMailAlert.identifier(for: alert.thread))",
            content: content,
            trigger: nil)
    }

    /// Posts each alert's notification. One iOS refuses is left out; the mail is as the rules left it either way.
    public static func post(_ alerts: [RuleAlert], in account: Account) async {
        let center = UNUserNotificationCenter.current()
        for alert in alerts { try? await center.add(request(for: alert, in: account)) }
    }
}
