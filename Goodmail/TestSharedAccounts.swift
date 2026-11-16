#if DEBUG
    import Foundation
    import MailCore

    /// Launch with `-GoodmailSeedSharedAccounts YES` to find accounts in iCloud Keychain as if another device shared
    /// them, so the offer and Other Devices can be seen on a simulator, which has no other device. Their sign-ins are
    /// placeholders, so they fail to sync once added.
    enum TestSharedAccounts {
        static func seedIfRequested() async {
            guard UserDefaults.standard.bool(forKey: "GoodmailSeedSharedAccounts") else { return }
            let accounts = [
                Account(
                    id: AccountID(rawValue: "seeded-gmail"), email: "dana.levi@gmail.com", color: .blue,
                    service: .gmail, name: "Dana Levi"),
                Account(
                    id: AccountID(rawValue: "seeded-outlook"), email: "dana@contoso.com", color: .orange,
                    service: .outlook),
                Account(
                    id: AccountID(rawValue: "seeded-icloud"), email: "dana.levi@icloud.com", color: .green,
                    service: .icloud),
            ]
            let placeholders = MemorySignIns(accounts.map { Providers.signInKey($0.id, $0.service) })
            do {
                try await AccountSharing(shared: Keychain.iCloud, device: placeholders, signInKey: Providers.signInKey)
                    .share(accounts)
            } catch {
                print("Seeding shared accounts failed: \(error)")
            }
        }

        /// A placeholder sign-in under each key, for `share` to copy.
        private struct MemorySignIns: SecretDirectory {
            let signIns: Set<String>

            init(_ keys: [String]) { signIns = Set(keys) }

            func data(for key: String) throws -> Data? { signIns.contains(key) ? Data("placeholder".utf8) : nil }
            func set(_ data: Data, for key: String) throws {}
            func remove(_ key: String) throws {}
            func keys() throws -> [String] { Array(signIns) }
        }
    }
#endif
