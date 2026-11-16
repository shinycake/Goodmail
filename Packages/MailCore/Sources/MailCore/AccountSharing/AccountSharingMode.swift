import Foundation

/// How this device takes part in sharing accounts through iCloud Keychain. Each device keeps its own.
public enum AccountSharingMode: String, CaseIterable, Sendable {
    /// Shares this device's accounts and offers the others' accounts, which the reader adds or not. A new device
    /// starts here.
    case offering
    /// Shares this device's accounts and follows the others: accounts added or removed elsewhere are added or removed
    /// here too. The reader chose it by accepting an offer, or in Settings.
    case following
    /// Shares nothing and offers nothing. The sign-ins already on this device stay.
    case off

    /// Whether this device's sign-ins go to, and come from, iCloud Keychain.
    public var shares: Bool { self != .off }

    /// Kept in the App Group, because the notification extension reads sign-ins the same way the app does.
    public static var current: AccountSharingMode {
        get { defaults.string(forKey: key).flatMap(AccountSharingMode.init(rawValue:)) ?? .offering }
        set { defaults.set(newValue.rawValue, forKey: key) }
    }

    private static let key = "accountSharingMode"
    private static var defaults: UserDefaults { UserDefaults(suiteName: SharedContainer.appGroupID) ?? .standard }
}
