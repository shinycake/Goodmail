import Foundation
import MailCore

/// Entity identifiers are strings: an account's ID, then the provider's IDs below it, each percent-encoded and joined
/// by `/`. Providers' IDs hold any character: an iCloud thread ID is a Message-ID such as `<CAF+x/a@b>`, its message
/// IDs name folders such as `INBOX/Sub`, and Outlook's are base64. Encoding every component keeps the separator
/// unambiguous.
enum EntityID {
    static func string(_ thread: ThreadSummary.ID) -> String {
        join([thread.accountID.rawValue, thread.threadID])
    }

    static func thread(_ string: String) -> ThreadSummary.ID? {
        guard let parts = split(string, count: 2) else { return nil }
        return ThreadSummary.ID(accountID: AccountID(rawValue: parts[0]), threadID: parts[1])
    }

    /// A message's identifier names its thread too, so it can be found among the thread's cached messages.
    static func string(_ message: Message.ID, inThread threadID: String) -> String {
        join([message.accountID.rawValue, threadID, message.messageID])
    }

    static func message(_ string: String) -> (thread: ThreadSummary.ID, message: Message.ID)? {
        guard let parts = split(string, count: 3) else { return nil }
        let account = AccountID(rawValue: parts[0])
        return (
            ThreadSummary.ID(accountID: account, threadID: parts[1]),
            Message.ID(accountID: account, messageID: parts[2])
        )
    }

    /// A mailbox belongs to one account here: the mail schema gives every mailbox an account. All Mail has no label,
    /// so its second component is empty.
    static func string(_ mailbox: Mailbox, account: AccountID) -> String {
        join([account.rawValue, mailbox.labelID ?? ""])
    }

    static func mailbox(_ string: String) -> Mailbox? {
        guard let parts = split(string, count: 2, allowingEmptyLast: true) else { return nil }
        return Mailbox(labelID: parts[1].isEmpty ? nil : parts[1], accountID: AccountID(rawValue: parts[0]))
    }

    /// Unreserved URL characters stay; everything else, `/` and `%` included, is encoded.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func join(_ components: [String]) -> String {
        components.map { $0.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $0 }.joined(separator: "/")
    }

    /// The `count` decoded components, or `nil` when the string isn't one of these identifiers.
    private static func split(_ string: String, count: Int, allowingEmptyLast: Bool = false) -> [String]? {
        let parts = string.split(separator: "/", omittingEmptySubsequences: false).map { $0.removingPercentEncoding }
        guard parts.count == count else { return nil }
        let decoded = parts.compactMap(\.self)
        guard decoded.count == count else { return nil }
        let required = allowingEmptyLast ? decoded.dropLast() : decoded[...]
        return required.allSatisfy({ !$0.isEmpty }) ? decoded : nil
    }
}
