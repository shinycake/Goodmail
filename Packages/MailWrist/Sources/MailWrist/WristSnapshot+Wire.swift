public import Foundation

extension WristSnapshot {
    /// What a received snapshot turned out to be.
    public enum Reading: Equatable, Sendable {
        case snapshot(WristSnapshot)
        /// Made by an app newer than this one, which has to be updated to read it.
        case newerVersion
    }

    /// The snapshot as it crosses to the other device.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Reads what `encoded()` made, by this app or another version of it.
    public static func read(_ data: Data) throws -> Reading {
        let version = try JSONDecoder().decode(Version.self, from: data).version
        guard version <= currentVersion else { return .newerVersion }
        return .snapshot(try JSONDecoder().decode(WristSnapshot.self, from: data))
    }

    /// The one field every version keeps.
    private struct Version: Decodable {
        let version: Int
    }
}
