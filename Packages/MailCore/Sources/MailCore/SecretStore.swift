import Foundation

/// Where credentials live. Production uses the shared `Keychain`; tests substitute memory.
public protocol SecretStore: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
}
