import Foundation

/// What `UID SEARCH` looks for (RFC 3501 §6.4.4): messages that meet every criterion set. IMAP dates are days, so
/// callers that need an exact time filter what comes back by `receivedAt`.
struct IMAPSearch: Equatable, Sendable {
    enum Flag: String, Sendable {
        case flagged = "FLAGGED"
        case unseen = "UNSEEN"
    }

    /// Only these UIDs. An upper bound of `UInt32.max` is written `*`.
    var uids: ClosedRange<UInt32>?
    /// Received on or after this date's day.
    var since: Date?
    /// Received before this date's day.
    var before: Date?
    var flag: Flag?

    var criteria: String {
        var criteria: [String] = []
        if let uids {
            let upper = uids.upperBound == .max ? "*" : "\(uids.upperBound)"
            criteria.append("UID \(uids.lowerBound):\(upper)")
        }
        if let since { criteria.append("SINCE \(IMAPCommand.searchDate(since))") }
        if let before { criteria.append("BEFORE \(IMAPCommand.searchDate(before))") }
        if let flag { criteria.append(flag.rawValue) }
        return criteria.isEmpty ? "ALL" : criteria.joined(separator: " ")
    }
}
