import Foundation

/// A person who sends mail, as Block Sender and VIPs know them: by address, lowercased and trimmed, so "Dana@X.com"
/// and "dana@x.com" are one person.
public struct SenderAddress: Hashable, Sendable {
    public let address: String

    /// `nil` for text that isn't an address: something on each side of an `@`.
    public init?(_ text: String) {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = address.firstIndex(of: "@"), at > address.startIndex,
            address.index(after: at) < address.endIndex
        else { return nil }
        self.address = address
    }

    /// Who sent mail from `sender`, or `nil` when the reader did, from one of `own`: nobody blocks or marks themselves.
    public init?(of sender: Contact, notFrom own: [String]) {
        guard let address = SenderAddress(sender.address),
            !own.contains(where: { SenderAddress($0) == address })
        else { return nil }
        self = address
    }

    /// The one person all of `senders` are, as when several picked conversations come from the same sender, or `nil`
    /// when they are from several people, or the reader.
    public static func shared(by senders: [Contact], notFrom own: [String]) -> SenderAddress? {
        let people = Set(senders.map { SenderAddress(of: $0, notFrom: own) })
        guard people.count == 1, let person = people.first else { return nil }
        return person
    }
}
