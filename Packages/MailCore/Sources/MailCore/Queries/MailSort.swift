import Foundation

/// The order a filter returns mail in: one key, then the next for ties, and newest first after them all.
public struct MailSort: Codable, Hashable, Sendable {
    public enum Key: String, CaseIterable, Codable, Hashable, Sendable {
        case date
        case subject
        /// The sender's name, or address when there is none.
        case sender
        case recipientCount
        case attachmentCount
        case attachmentSize
        case messageCount
        case largestAmount
        case totalAmount
    }

    public var key: Key
    public var ascending: Bool

    public init(_ key: Key, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    /// Newest first, the order every list shows.
    public static let newestFirst = MailSort(.date, ascending: false)

    /// `mail` sorted by `sorts`. Mail with no value for a key, as a receipt-less mail sorted by amount, goes after
    /// the rest whichever way the key runs.
    public static func sorted(_ mail: [MailFacts], by sorts: [MailSort]) -> [MailFacts] {
        let order = sorts + [.newestFirst]
        // Each key is read once per mail: amounts come from scanning the body.
        let keyed = mail.map { facts in (facts, order.map { $0.key.value(of: facts) }) }
        return keyed.sorted { lhs, rhs in
            for (index, sort) in order.enumerated() {
                switch (lhs.1[index], rhs.1[index]) {
                case (nil, nil): continue
                case (nil, _): return false
                case (_, nil): return true
                case (let left?, let right?):
                    if left == right { continue }
                    return sort.ascending ? left < right : right < left
                }
            }
            return false
        }.map(\.0)
    }
}

/// One mail's value for a sort key.
enum SortValue: Comparable {
    case number(Double)
    case text(String)
    case date(Date)

    static func < (lhs: SortValue, rhs: SortValue) -> Bool {
        switch (lhs, rhs) {
        case (.number(let a), .number(let b)): a < b
        case (.text(let a), .text(let b)): a.localizedStandardCompare(b) == .orderedAscending
        case (.date(let a), .date(let b)): a < b
        default: false
        }
    }
}

extension MailSort.Key {
    func value(of mail: MailFacts) -> SortValue? {
        switch self {
        case .date: .date(mail.envelope.date)
        case .subject: .text(mail.envelope.subject)
        case .sender: .text(mail.envelope.sender.displayName)
        case .recipientCount: mail.number(.recipientCount).map(SortValue.number)
        case .attachmentCount: mail.number(.attachmentCount).map(SortValue.number)
        case .attachmentSize: mail.number(.attachmentSize).map(SortValue.number)
        case .messageCount: mail.number(.messageCount).map(SortValue.number)
        case .largestAmount: mail.number(.largestAmount).map(SortValue.number)
        case .totalAmount: mail.number(.totalAmount).map(SortValue.number)
        }
    }
}
