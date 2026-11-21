/// The people the reader marked as VIPs, in the order they were added. The VIPs smart mailbox and filter read their
/// mail through `condition`.
public struct VIPList: Equatable, Sendable {
    public private(set) var senders: [SenderAddress] = []

    /// The VIPs from stored addresses, once each, leaving out text that isn't an address.
    public init(_ addresses: [String] = []) {
        for case let sender? in addresses.map(SenderAddress.init) { set(sender, isVIP: true) }
    }

    /// The VIPs' addresses, lowercased, as the store keeps them.
    public var addresses: [String] { senders.map(\.address) }

    public func contains(_ sender: SenderAddress) -> Bool {
        senders.contains(sender)
    }

    /// Adds `sender` last, or takes them off. Either is a no-op when they already are, or aren't, a VIP.
    public mutating func set(_ sender: SenderAddress, isVIP: Bool) {
        if isVIP {
            if !contains(sender) { senders.append(sender) }
        } else {
            senders.removeAll { $0 == sender }
        }
    }

    /// The VIPs' mail: from any of them. With no VIPs it holds nothing, as an empty `any` never does.
    public var condition: MailCondition {
        .any(senders.map { .text(.senderAddress, .equals($0.address)) })
    }
}
