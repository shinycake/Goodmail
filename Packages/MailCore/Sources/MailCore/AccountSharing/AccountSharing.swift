import Foundation

/// Reads and writes the accounts kept in the Keychain: one record per account beside its sign-in, shared through
/// iCloud Keychain with the reader's other devices, and another on this device alone, which outlives deleting the app
/// so a reinstall can restore its accounts. The Keychain blocks, so every call runs off the caller's actor.
public struct AccountSharing: Sendable {
    /// The shared place: iCloud Keychain in the app.
    private let shared: any SecretDirectory
    /// Where this device keeps its own sign-ins, and its own record of each account.
    private let device: any SecretDirectory
    /// The key an account's sign-in is stored under, which depends on its service.
    private let signInKey: @Sendable (AccountID, MailService) -> String

    public init(
        shared: any SecretDirectory, device: any SecretDirectory,
        signInKey: @escaping @Sendable (AccountID, MailService) -> String
    ) {
        self.shared = shared
        self.device = device
        self.signInKey = signInKey
    }

    /// How `local`, this device's accounts in order, differ from the shared ones.
    @concurrent public func plan(for local: [Account]) async throws -> AccountSharingPlan {
        let records = try Self.records(in: shared)
        return AccountSharingPlan(local: local, shared: records) { id, service in
            (try? shared.data(for: signInKey(id, service))) != nil
        }
    }

    /// Shares `accounts`, in this order, with their sign-ins. An account already shared gets its name, nickname,
    /// color and place updated; one removed on another device stays removed.
    @concurrent public func share(_ accounts: [Account]) async throws {
        let records = try Self.records(in: shared)
        let places = SharedOrder.places(
            of: accounts.map(\.id), shared: records.compactMapValues(\.profile).mapValues(\.position))
        for account in accounts {
            let key = Self.recordKey(account.id)
            let record = SharedAccount.present(SharedAccount.Profile(account, position: places[account.id] ?? 0))
            let stored = records[account.id]
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

    /// Keeps this device's own record of `accounts`, in this order, whether or not it shares them, so a reinstall
    /// finds them.
    @concurrent public func remember(_ accounts: [Account]) async throws {
        let records = try Self.records(in: device)
        for (position, account) in accounts.enumerated() {
            let record = SharedAccount.present(SharedAccount.Profile(account, position: position))
            guard records[account.id] != record else { continue }
            try device.set(try JSONEncoder().encode(record), for: Self.recordKey(account.id))
        }
    }

    /// Forgets this device's record of the account, so a reinstall doesn't bring back what the reader removed.
    @concurrent public func forget(_ id: AccountID) async throws {
        try device.set(try JSONEncoder().encode(SharedAccount.removed), for: Self.recordKey(id))
    }

    /// The accounts this device remembers and still has the sign-in of, but not among `local`: what a reinstall can
    /// restore, in their order.
    @concurrent public func restorable(for local: [Account]) async throws -> [Account] {
        let here = Set(local.map(\.id))
        return try Self.records(in: device).compactMapValues(\.profile)
            .filter { id, profile in
                try !here.contains(id) && device.data(for: signInKey(id, profile.service)) != nil
            }
            .sorted { ($0.value.position, $0.key.rawValue) < ($1.value.position, $1.key.rawValue) }
            .map { id, profile in profile.account(id) }
    }

    /// Every record in `directory`, by account. One this build can't read, as a newer build's, is left out.
    private static func records(in directory: any SecretDirectory) throws -> [AccountID: SharedAccount] {
        var records: [AccountID: SharedAccount] = [:]
        for key in try directory.keys() where key.hasPrefix(recordPrefix) {
            guard let data = try directory.data(for: key),
                let record = try? JSONDecoder().decode(SharedAccount.self, from: data)
            else { continue }
            records[AccountID(rawValue: String(key.dropFirst(recordPrefix.count)))] = record
        }
        return records
    }

    private static let recordPrefix = "account."
    private static func recordKey(_ id: AccountID) -> String { recordPrefix + id.rawValue }
}
