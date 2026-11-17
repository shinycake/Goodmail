public import Foundation

/// What this device has synced of each group, and the name it stamps its changes with. Kept on the device alone: a
/// reinstall starts without one, so it takes up the shared settings rather than its defaults.
public struct SettingsLedger: Codable, Equatable, Sendable {
    public var device: String
    public var families: [String: [String: SyncedEntry]]

    public init(device: String = UUID().uuidString, families: [String: [String: SyncedEntry]] = [:]) {
        self.device = device
        self.families = families
    }
}

public protocol SettingsLedgerStore: Sendable {
    /// The ledger kept, or `nil` before the first sync.
    func load() throws -> SettingsLedger?
    func save(_ ledger: SettingsLedger) throws
}

/// The ledger as a file.
public struct SettingsLedgerFile: SettingsLedgerStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> SettingsLedger? {
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        return try JSONDecoder().decode(SettingsLedger.self, from: Data(contentsOf: url))
    }

    public func save(_ ledger: SettingsLedger) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ledger).write(to: url, options: .atomic)
    }
}
