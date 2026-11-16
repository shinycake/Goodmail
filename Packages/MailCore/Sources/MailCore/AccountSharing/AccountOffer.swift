/// The accounts a device offers to add without a sign-in, because their sign-ins are in the Keychain already.
public struct AccountOffer: Equatable, Sendable {
    /// Where the offered accounts were set up, which is what the offer says.
    public enum Origin: Equatable, Sendable {
        /// On the reader's other devices, through iCloud Keychain.
        case otherDevices
        /// On this device, before the app was deleted and installed again. Any the other devices add come along.
        case thisDevice
    }

    public let accounts: [Account]
    public let origin: Origin

    public init(accounts: [Account], origin: Origin) {
        self.accounts = accounts
        self.origin = origin
    }

    /// This device's own accounts from before a reinstall, then the other devices' it doesn't have; or else only the
    /// other devices'. None the reader turned down. `nil` when that leaves nothing.
    public init?(restorable: [Account], elsewhere: [Account], declined: Set<AccountID>) {
        let restoring = restorable.filter { !declined.contains($0.id) }
        let others = elsewhere.filter { shared in
            !declined.contains(shared.id) && !restoring.contains { $0.id == shared.id }
        }
        if !restoring.isEmpty {
            self.init(accounts: restoring + others, origin: .thisDevice)
        } else if !others.isEmpty {
            self.init(accounts: others, origin: .otherDevices)
        } else {
            return nil
        }
    }
}
