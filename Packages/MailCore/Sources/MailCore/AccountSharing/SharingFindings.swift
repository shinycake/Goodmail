/// What the last pass with the reader's other devices found to offer: this device's accounts from before the app was
/// deleted, and the other devices' accounts. Kept as found and read against the accounts here now, so one the reader
/// added since, by signing in or from the offer, is never offered again, and none needs taking out by hand.
public struct SharingFindings: Equatable, Sendable {
    private var restorable: [Account]
    private var elsewhere: [Account]

    /// `elsewhere` is empty while this device doesn't share its accounts.
    public init(restorable: [Account] = [], elsewhere: [Account] = []) {
        self.restorable = restorable
        self.elsewhere = elsewhere
    }

    /// A pass read the accounts to restore. One that couldn't keeps what the last found.
    public mutating func found(restorable: [Account]) {
        self.restorable = restorable
    }

    /// A pass read the other devices' accounts, or found this device doesn't share, with none.
    public mutating func found(elsewhere: [Account]) {
        self.elsewhere = elsewhere
    }

    /// The account was removed from this device, its sign-in with it, so there's nothing of it left to restore.
    public mutating func removed(_ id: AccountID) {
        restorable.removeAll { $0.id == id }
    }

    /// This device's accounts from before a reinstall, whose sign-ins are still in its Keychain, that aren't `here`.
    public func restorable(besides here: [Account]) -> [Account] {
        restorable.filter { found in !here.contains { $0.id == found.id } }
    }

    /// The other devices' accounts that aren't `here`.
    public func elsewhere(besides here: [Account]) -> [Account] {
        elsewhere.filter { found in !here.contains { $0.id == found.id } }
    }
}
