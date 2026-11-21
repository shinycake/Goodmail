public import Foundation

/// A snooze as the reader's devices share it (ADR-037): asleep until a time, or woken at one. Who keeps it stays on
/// each device, since it's the device that snoozed it and nothing to share: a device taking it up from the others
/// keeps it as theirs (`takenUp`).
public enum SharedSnooze: Codable, Hashable, Sendable {
    case asleep(until: Date)
    case woke(at: Date)

    public init(_ state: SnoozeState) {
        switch state {
        case .asleep(let until, _): self = .asleep(until: until)
        case .woke(let at): self = .woke(at: at)
        }
    }

    /// The snooze this device keeps when it takes this one up from another device.
    public var takenUp: SnoozeState {
        switch self {
        case .asleep(let until): .asleep(until: until, keeper: .otherDevice)
        case .woke(let at): .woke(at: at)
        }
    }

    /// The snooze in `data`.
    public init(_ data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    /// The snooze in `data`, or `nil` when a newer build wrote a form this one can't read.
    public static func decoding(_ data: Data) -> Self? {
        try? Self(data)
    }

    /// As JSON with sorted keys, so the same snooze always reads the same and isn't taken for an edit.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
}
