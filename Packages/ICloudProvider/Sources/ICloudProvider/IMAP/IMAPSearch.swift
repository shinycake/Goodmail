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
    /// Only the message with this RFC 5322 Message-ID, bare (without angle brackets).
    var messageID: String?
    /// Only messages with every word somewhere in their headers or body.
    var text: String?

    /// Throws `IMAPError.unencodable` for a Message-ID a quoted string can't carry.
    var criteria: [IMAPCommand.Argument] {
        get throws {
            let words = text?.split(whereSeparator: \.isWhitespace) ?? []
            let other = try otherCriteria
            var criteria: [IMAPCommand.Argument] = []
            if !words.isEmpty { criteria.append(.text("CHARSET UTF-8")) }
            if !other.isEmpty { criteria.append(.text(other.joined(separator: " "))) }
            // Each word goes as a UTF-8 literal, which carries any script and any punctuation.
            for word in words { criteria += [.text("TEXT"), .literal(Data(word.utf8))] }
            return criteria.isEmpty ? [.text("ALL")] : criteria
        }
    }

    private var otherCriteria: [String] {
        get throws {
            var criteria: [String] = []
            if let uids {
                let upper = uids.upperBound == .max ? "*" : "\(uids.upperBound)"
                criteria.append("UID \(uids.lowerBound):\(upper)")
            }
            if let since { criteria.append("SINCE \(IMAPCommand.searchDate(since))") }
            if let before { criteria.append("BEFORE \(IMAPCommand.searchDate(before))") }
            if let flag { criteria.append(flag.rawValue) }
            // iCloud matches the header's whole value, angle brackets and all, where RFC 3501 asks for a substring; the
            // bracketed ID satisfies both.
            if let messageID { criteria.append("HEADER Message-ID \(try IMAPCommand.quoted("<\(messageID)>"))") }
            return criteria
        }
    }
}
