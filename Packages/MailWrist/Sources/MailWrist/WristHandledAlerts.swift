public import Foundation
import MailCore

/// An alert the relay sent the watch itself (ADR-023), as the watch finds it in Notification Center.
public struct WristDeliveredAlert: Sendable {
    /// The identifier watchOS removes it by.
    public let identifier: String
    /// The relay's payload, its string values only (PushWorker/README.md).
    public let payload: [String: String]
    public let deliveredAt: Date

    public init(identifier: String, payload: [String: String], deliveredAt: Date) {
        self.identifier = identifier
        self.payload = payload
        self.deliveredAt = deliveredAt
    }
}

extension WristMailbox {
    /// How far a conversation's date may fall before its alert's delivery and still be the alerted mail: the relay
    /// alerts within seconds, and the watch's copy waits for the iPhone first.
    static let deliveryLag: TimeInterval = 10 * 60

    /// The identifiers of the `alerts` whose mail the reader has dealt with since, as the Inbox the watch holds says:
    /// the conversation read, or, in a copy that holds mail as new as the alert, gone from a list that would hold it
    /// or its account left with nothing unread. Each account is judged by its own source's copy: the watch's for one
    /// it reads itself, the iPhone's for the rest. A copy's own date says only when it was sent, and the relay alerts
    /// the watch just when the iPhone may not have the mail, so only mail as new as the alert shows a copy caught up.
    /// An alert whose account or conversation the copy can't place stays.
    public func handledAlerts(_ alerts: [WristDeliveredAlert]) -> [String] {
        alerts.filter(isHandled).map(\.identifier)
    }

    private func isHandled(_ alert: WristDeliveredAlert) -> Bool {
        guard let phone = snapshot,
            let id = WristAlertTarget.account(in: alert.payload, among: phone.accounts)
        else { return false }
        guard let copy = sources[id] == .direct ? own : phone, let account = copy.account(id) else { return false }
        let since = alert.deliveredAt.addingTimeInterval(-Self.deliveryLag)
        let isCaughtUp = copy.rows.contains { $0.id.accountID == id && $0.date >= since }
        if isCaughtUp && account.unread == 0 { return true }
        guard let threadID = alert.payload["threadID"], !threadID.isEmpty else { return false }
        let thread = ThreadSummary.ID(accountID: id, threadID: threadID)
        if let row = copy.rows.first(where: { $0.id == thread }) {
            // A conversation still unread, or read before newer mail in it alerted, keeps the alert.
            return !row.isUnread && row.date >= since
        }
        // Missing from a full list whose oldest conversation is older than this mail: it left the Inbox.
        let listed = copy.rows.filter { !$0.isPinned }
        let reaches = copy.rows.count < WristSnapshot.rowLimit || listed.contains { $0.date < since }
        return isCaughtUp && reaches
    }
}
