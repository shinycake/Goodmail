public import Foundation

/// The sign-ins of a device that shares its accounts: each lives on the device and, kept in step, in iCloud Keychain,
/// where the reader's other devices find it. Reads prefer the shared copy, which holds the newest token whichever
/// device refreshed last; writes and removals reach both. The device copy is what's left when sharing stops.
public struct SharedSecrets: SecretStore {
    private let device: any SecretStore
    private let shared: any SecretStore

    public init(device: any SecretStore, shared: any SecretStore) {
        self.device = device
        self.shared = shared
    }

    /// The shared copy, also kept on the device when it differs there, as for an account another device added.
    /// A sign-in only the device has is read from there and not shared: it may be one removed on another device.
    public func data(for key: String) throws -> Data? {
        guard let data = try shared.data(for: key) else { return try device.data(for: key) }
        if try device.data(for: key) != data { try device.set(data, for: key) }
        return data
    }

    public func set(_ data: Data, for key: String) throws {
        try device.set(data, for: key)
        try shared.set(data, for: key)
    }

    public func remove(_ key: String) throws {
        try device.remove(key)
        try shared.remove(key)
    }
}
