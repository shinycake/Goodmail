import Foundation

/// Who a message is from and for, as a reader checks it: a display name can say anything, so the sender's address
/// shows beside it, along with where replies really go and every recipient.
public struct MessageHeader: Equatable, Sendable {
    /// One recipient field that names anyone, in header order.
    public struct Field: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case to, cc, bcc
        }

        public let kind: Kind
        public let contacts: [Contact]

        public init(kind: Kind, contacts: [Contact]) {
            self.kind = kind
            self.contacts = contacts
        }
    }

    public let sender: Contact
    /// The sender's address, when a name stands in for it on screen.
    public let senderAddress: String?
    /// Where a reply goes when that isn't the sender. Empty when Reply-To is missing or only names the sender.
    public let replyTo: [Contact]
    public let fields: [Field]

    public init(_ message: Message) {
        sender = message.from
        senderAddress = message.from.displayName == message.from.address ? nil : message.from.address
        replyTo =
            message.replyTo.allSatisfy { $0.address.caseInsensitiveCompare(message.from.address) == .orderedSame }
            ? [] : message.replyTo
        fields = [
            Field(kind: .to, contacts: message.to), Field(kind: .cc, contacts: message.cc),
            Field(kind: .bcc, contacts: message.bcc),
        ]
        .filter { !$0.contacts.isEmpty }
    }

    /// Everyone the message went to, To first.
    public var recipients: [Contact] { fields.flatMap(\.contacts) }
}
