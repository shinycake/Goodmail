import Foundation
import GmailProvider
public import MailCore
public import MailWrist
import OutlookProvider

/// The sign-ins this watch holds (ADR-023). Nobody signs in on the watch: the iPhone's sign-ins reach it through
/// iCloud Keychain, where the iPhone already shares them, and the watch keeps a device copy of each.
///
/// The watch reads and refreshes through both copies, so a token Microsoft rotated here reaches the iPhone. It never
/// removes the shared copy: that belongs to the reader's other devices, and only the iPhone signs an account out.
public struct WristSignIns: Sendable {
    /// What an account's session reads and writes.
    let secrets: any SecretStore
    private let device: any SecretStore

    /// `device` is the watch's own Keychain; `shared` the iCloud Keychain items the iPhone writes.
    public init(device: any SecretStore, shared: any SecretStore) {
        self.device = device
        secrets = KeptShared(both: SharedSecrets(device: device, shared: shared), device: device)
    }

    /// The accounts among `accounts` whose sign-in is on this watch. Only Gmail and Outlook keep one the watch can use.
    public func held(by accounts: [WristAccount]) throws -> Set<AccountID> {
        var held: Set<AccountID> = []
        for account in accounts {
            guard let key = Self.key(for: account), try secrets.data(for: key) != nil else { continue }
            held.insert(account.id)
        }
        return held
    }

    /// Forgets the watch's copy of the account's sign-in, as after the iPhone removed the account. The shared copy
    /// stays.
    public func forget(_ account: WristAccount) throws {
        guard let key = Self.key(for: account) else { return }
        try device.remove(key)
    }

    /// Keeps `refreshToken` as the account's sign-in on this watch alone, as a simulator needs, where iCloud Keychain
    /// brings none. An account the watch can't reach keeps nothing.
    public func keepOnDevice(refreshToken: String, for account: WristAccount) throws {
        guard let key = Self.key(for: account) else { return }
        try device.set(Data(refreshToken.utf8), for: key)
    }

    /// The OAuth service that signs `account` in, or `nil` for one the watch can't reach.
    static func client(for account: WristAccount) -> OAuthClient? {
        switch account.service {
        case .gmail: .gmail
        case .outlook: .outlook
        case .icloud, .imap, nil: nil
        }
    }

    private static func key(for account: WristAccount) -> String? {
        client(for: account)?.refreshTokenKey(account.id)
    }
}

/// Both copies for reads and writes, but only the device's for removals.
private struct KeptShared: SecretStore {
    let both: SharedSecrets
    let device: any SecretStore

    func data(for key: String) throws -> Data? { try both.data(for: key) }
    func set(_ data: Data, for key: String) throws { try both.set(data, for: key) }
    func remove(_ key: String) throws { try device.remove(key) }
}
