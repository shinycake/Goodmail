#if canImport(Security)
    import Foundation
    import Security

    /// Secrets shared by the app and its extensions. Items are readable after first unlock, so the NSE can
    /// use them while the phone is locked. The access group is the entitlement's first one, the shared group.
    public struct Keychain: SecretStore {
        public struct Failure: LocalizedError, Equatable {
            public let status: OSStatus

            public var errorDescription: String? {
                "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
            }
        }

        private let service: String

        public init(service: String = "com.idanbirman.goodmail") {
            self.service = service
        }

        public func data(for key: String) throws -> Data? {
            var query = baseQuery(for: key)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
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
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw Failure(status: status) }
        }

        public func remove(_ key: String) throws {
            let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
        }

        private func baseQuery(for key: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
        }
    }
#endif
