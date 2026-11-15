import Foundation

/// The senders whose remote images always load, kept on this device by address. Addresses compare without case or
/// surrounding space, and are kept sorted so Settings lists them in order.
public struct TrustedImageSenders {
    private let key: String
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, key: String = "trustedImageSenders") {
        self.defaults = defaults
        self.key = key
    }

    /// Every trusted address, in alphabetical order.
    public var addresses: [String] { defaults.stringArray(forKey: key) ?? [] }

    public func contains(_ address: String) -> Bool {
        addresses.contains(Self.normalized(address))
    }

    /// Trusts `address` from now on. An empty address, as from a message with no sender, is never trusted.
    public func trust(_ address: String) {
        let address = Self.normalized(address)
        guard !address.isEmpty else { return }
        store(Set(addresses).union([address]))
    }

    public func distrust(_ address: String) {
        store(Set(addresses).subtracting([Self.normalized(address)]))
    }

    private func store(_ addresses: Set<String>) {
        defaults.set(addresses.sorted(), forKey: key)
    }

    static func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
