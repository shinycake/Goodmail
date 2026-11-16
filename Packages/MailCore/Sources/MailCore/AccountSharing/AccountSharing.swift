import Foundation

/// Reads and writes the accounts the reader's devices share in iCloud Keychain: one record per account, beside its
/// shared sign-in. The Keychain blocks, so every call runs off the caller's actor.
public struct AccountSharing: Sendable {
    /// The shared place: iCloud Keychain in the app.
    private let shared: any SecretDirectory
    /// Where this device keeps its own sign-ins.
    private let device: any SecretStore
    /// The key an account's sign-in is stored under, which depends on its service.
    private let signInKey: @Sendable (AccountID, MailService) -> String

    public init(
        shared: any SecretDirectory, device: any SecretStore,
        signInKey: @escaping @Sendable (AccountID, MailService) -> String
    ) {
        self.shared = shared
        self.device = device
        self.signInKey = signInKey
    }

    /// How `local`, this device's accounts in order, differ from the shared ones.
    @concurrent public func plan(for local: [Account]) async throws -> AccountSharingPlan {
        let records = try records()
        return AccountSharingPlan(local: local, shared: records) { id, service in
            (try? shared.data(for: signInKey(id, service))) != nil
        }
    }

    /// Shares `accounts`, in this order, with their sign-ins. An account already shared gets its name, color and
    /// place updated; one removed on another device stays removed.
    @concurrent public func share(_ accounts: [Account]) async throws {
        for (position, account) in accounts.enumerated() {
            let key = Self.recordKey(account.id)
            let record = SharedAccount.present(SharedAccount.Profile(account, position: position))
            let stored = try shared.data(for: key).flatMap { try? JSONDecoder().decode(SharedAccount.self, from: $0) }
            guard stored != .removed, stored != record else { continue }
            let signIn = signInKey(account.id, account.service)
            // The shared sign-in, when there is one, is at least as new as the device's.
            if try shared.data(for: signIn) == nil, let login = try device.data(for: signIn) {
                try shared.set(login, for: signIn)
            }
            try shared.set(try JSONEncoder().encode(record), for: key)
        }
    }

    /// Tells the other devices the account was removed. Its shared sign-in leaves with the device's (SharedSecrets).
    @concurrent public func retire(_ id: AccountID) async throws {
        try shared.set(try JSONEncoder().encode(SharedAccount.removed), for: Self.recordKey(id))
    }

    /// Every record, by account. One this build can't read, as a newer build's, is left out.
    private func records() throws -> [AccountID: SharedAccount] {
        var records: [AccountID: SharedAccount] = [:]
        for key in try shared.keys() where key.hasPrefix(Self.recordPrefix) {
            guard let data = try shared.data(for: key),
                let record = try? JSONDecoder().decode(SharedAccount.self, from: data)
            else { continue }
            records[AccountID(rawValue: String(key.dropFirst(Self.recordPrefix.count)))] = record
        }
        return records
    }

    private static let recordPrefix = "account."
    private static func recordKey(_ id: AccountID) -> String { recordPrefix + id.rawValue }
}
