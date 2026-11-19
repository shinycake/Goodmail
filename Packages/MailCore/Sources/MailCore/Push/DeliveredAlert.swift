public import Foundation

/// An alert in Notification Center that names a thread, as far as telling whether the reader has dealt with its mail
/// since, here, on another device or in another app. `MailDatabase.handledAlerts(_:)` says which have.
public struct DeliveredAlert: Equatable, Sendable {
    /// What took the alert's mail off the reader's plate depends on why it alerted.
    public enum Kind: Equatable, Sendable {
        /// The app's alert for new mail it stored before alerting: dealt with once read, out of the Inbox, or gone.
        case newMail
        /// A push iOS showed as the relay sent it, because the extension couldn't fetch its mail in time, or quietly
        /// as a placeholder: dealt with once its thread is stored as of the alert or later, and read or out of the
        /// Inbox. Mail not stored yet, or stored only as it was before, is still owed.
        case relayed
        /// A rule's notification, about mail the rule may have filed itself: dealt with once read, in Trash or Spam,
        /// or gone.
        case rule
    }

    /// The identifier iOS removes it by.
    public let identifier: String
    public let thread: ThreadSummary.ID
    public let kind: Kind
    /// When iOS delivered it.
    public let deliveredAt: Date

    /// How a rule's notification identifier starts (`RuleNotification`).
    public static let rulePrefix = "rule/"

    public init(identifier: String, thread: ThreadSummary.ID, kind: Kind, deliveredAt: Date) {
        self.identifier = identifier
        self.thread = thread
        self.kind = kind
        self.deliveredAt = deliveredAt
    }

    /// The alert iOS delivered as `identifier` with `userInfo` at `deliveredAt`, or `nil` for one this doesn't own:
    /// one that names no thread, as an IMAP push shown as sent names only its account, and one another feature
    /// posts under its own identifier, such as a snooze alarm (`snooze/…`).
    ///
    /// The sweep owns the alerts the extension hands iOS for a push, under the push's own identifier, which holds no
    /// `/`; the extra alerts it posts for other threads, as `<account>/<thread>` (`NewMailAlert.identifier`); and
    /// rules' notifications. The app's own alerts carry `AlertedThread`'s keys and nothing else. A push shown as sent
    /// carries the relay's payload, `aps` and all (PushWorker/README.md): Outlook's names its account by ID and
    /// Gmail's by address (looked up in `accounts`), each beside the conversation's `threadID`.
    public init?(identifier: String, userInfo: [AnyHashable: Any], deliveredAt: Date, accounts: [Account]) {
        guard let thread = AlertedThread.thread(in: userInfo) ?? Self.addressed(userInfo, among: accounts) else {
            return nil
        }
        let isOwned =
            identifier.hasPrefix(Self.rulePrefix) || !identifier.contains("/")
            || identifier == "\(thread.accountID.rawValue)/\(thread.threadID)"
        guard isOwned else { return nil }
        let kind: Kind =
            if identifier.hasPrefix(Self.rulePrefix) {
                .rule
            } else if userInfo["aps"] != nil {
                .relayed
            } else {
                .newMail
            }
        self.init(identifier: identifier, thread: thread, kind: kind, deliveredAt: deliveredAt)
    }

    /// The thread a Gmail push shown as sent names: its account by address, and the conversation.
    private static func addressed(_ userInfo: [AnyHashable: Any], among accounts: [Account]) -> ThreadSummary.ID? {
        guard let address = userInfo["account"] as? String, let thread = userInfo["threadID"] as? String,
            !thread.isEmpty,
            let account = accounts.first(where: { $0.email.caseInsensitiveCompare(address) == .orderedSame })
        else { return nil }
        return ThreadSummary.ID(accountID: account.id, threadID: thread)
    }
}
