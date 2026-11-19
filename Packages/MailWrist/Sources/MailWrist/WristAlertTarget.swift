import Foundation
public import MailCore

/// Where a tap on an alert the relay sent the watch itself opens (ADR-023): the conversation, when the watch reads
/// the account itself and the alert names one, otherwise the Inbox.
public enum WristAlertTarget: Equatable, Sendable {
    case inbox
    case thread(ThreadSummary.ID)

    /// The target of the relay's `payload` (PushWorker/README.md): Gmail names its account by `account`, the address,
    /// and the others by `accountID`; Gmail and Outlook name the conversation by `threadID`.
    public init(payload: [AnyHashable: Any], accounts: [WristAccount], sources: [AccountID: WristAccountSource]) {
        guard let thread = payload["threadID"] as? String, !thread.isEmpty,
            let account = Self.account(in: payload, among: accounts), sources[account] == .direct
        else {
            self = .inbox
            return
        }
        self = .thread(ThreadSummary.ID(accountID: account, threadID: thread))
    }

    static func account(in payload: [AnyHashable: Any], among accounts: [WristAccount]) -> AccountID? {
        if let id = payload["accountID"] as? String {
            return accounts.first { $0.id.rawValue == id }?.id
        }
        guard let address = payload["account"] as? String else { return nil }
        return accounts.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }?.id
    }
}
