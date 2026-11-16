#if canImport(Security)
    public import Foundation
    import Security

    /// Secrets shared by the app and its extensions. Items are readable after first unlock, so the NSE can
    /// use them while the phone is locked. The access group is the entitlement's first one, the shared group.
    public struct Keychain: SecretDirectory {
        public struct Failure: LocalizedError, Equatable {
            public let status: OSStatus

            public var errorDescription: String? {
                "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
            }
        }

        /// Where the items live.
        public enum Place: Sendable {
            /// On this device only.
            case device
            /// In iCloud Keychain, which syncs them, end-to-end encrypted, to the reader's other devices.
            case iCloud
        }

        private let service: String
        private let place: Place

        public init(service: String = "com.idanbirman.goodmail", place: Place = .device) {
            self.service = service
            self.place = place
        }

        /// The accounts' records and sign-ins that every device of the reader shares.
        public static let iCloud = Keychain(service: "com.idanbirman.goodmail.shared", place: .iCloud)

        /// Where the accounts' sign-ins are read and written: the device alone, or kept in step with iCloud
        /// Keychain while this device shares its accounts (`AccountSharingMode`).
        public static func signIns() -> any SecretStore {
            AccountSharingMode.current.shares ? SharedSecrets(device: Keychain(), shared: iCloud) : Keychain()
        }

        public func data(for key: String) throws -> Data? {
            var query = baseQuery(for: key)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            // Unsafe because `&result` passes a pointer. Safe: Security writes one retained object through it before
            // returning, and nothing keeps the pointer.
            let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw Failure(status: status) }
            return result as? Data
        }

        public func set(_ data: Data, for key: String) throws {
            let update = [kSecValueData as String: data]
            var status = SecItemUpdate(baseQuery(for: key) as CFDictionary, update as CFDictionary)
            if status == errSecItemNotFound {
                var item = baseQuery(for: key)
                item[kSecValueData as String] = data
                // A synced item can't be tied to this device.
                item[kSecAttrAccessible as String] =
                    switch place {
                    case .device: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                    case .iCloud: kSecAttrAccessibleAfterFirstUnlock
                    }
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw Failure(status: status) }
        }

        public func remove(_ key: String) throws {
            let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
        }

        public func keys() throws -> [String] {
            var query = baseQuery()
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitAll
            var result: CFTypeRef?
            // Unsafe because `&result` passes a pointer. Safe: as in `data(for:)`.
            let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return [] }
            guard status == errSecSuccess else { throw Failure(status: status) }
            let items = result as? [[String: Any]] ?? []
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        }

        private func baseQuery(for key: String? = nil) -> [String: Any] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                // Without it, a query finds only items that don't sync; said either way so each place is explicit.
                kSecAttrSynchronizable as String: place == .iCloud,
            ]
            if let key { query[kSecAttrAccount as String] = key }
            return query
        }
    }
#endif
