public import Foundation
import MailCore

/// The lists the reader has left on this device, so their mail stops offering Unsubscribe. Kept by account and
/// sender address, newest last, and trimmed to the most recent `limit`.
public struct UnsubscribedLists {
    private let key: String
    private let limit: Int
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, key: String = "unsubscribedLists", limit: Int = 500) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    func contains(_ address: String, account: AccountID) -> Bool {
        entries.contains(Self.entry(address, account: account))
    }

    func insert(_ address: String, account: AccountID) {
        let entry = Self.entry(address, account: account)
        defaults.set(Array((entries.filter { $0 != entry } + [entry]).suffix(limit)), forKey: key)
    }

    private var entries: [String] { defaults.stringArray(forKey: key) ?? [] }

    private static func entry(_ address: String, account: AccountID) -> String {
        "\(account.rawValue)\n\(address.lowercased())"
    }
}
