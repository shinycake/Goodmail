public import Foundation

/// When a setting got its value and on which device, so the reader's devices agree on the newest. Two edits at the
/// same moment are ordered by device, so every device picks the same one.
public struct SettingStamp: Codable, Comparable, Hashable, Sendable {
    public var time: Date
    public var device: String

    public init(time: Date, device: String) {
        self.time = time
        self.device = device
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.time, lhs.device) < (rhs.time, rhs.device)
    }
}

/// One setting as the reader's devices share it: its value, or that it was removed, as of a stamp. A removal stays
/// for a while as an entry of its own, so a device that still has the value learns it went rather than sharing it
/// again.
public enum SyncedEntry: Codable, Hashable, Sendable {
    case value(Data, SettingStamp)
    case removed(SettingStamp)

    public var stamp: SettingStamp {
        switch self {
        case .value(_, let stamp), .removed(let stamp): stamp
        }
    }

    public var value: Data? {
        switch self {
        case .value(let data, _): data
        case .removed: nil
        }
    }
}

/// What a sync does to one of this device's settings.
public enum SettingChange: Hashable, Sendable {
    case set(Data)
    case removed
}
