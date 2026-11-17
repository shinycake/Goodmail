public import Foundation

/// A group of settings kept in one place on the device and shared as one record: the reader's preferences, each
/// account's signature, the rules. Each setting in it is an element, merged on its own, so editing two settings of a
/// group on two devices keeps both edits. Reads and writes may block, so the sync calls them off the main actor.
public protocol SettingsFamily: Sendable {
    /// The name the group is shared under. Never changes once shipped.
    var name: String { get }

    /// The settings as this device has them now.
    func local() throws -> LocalSettings

    /// Takes up what the other devices changed.
    func apply(_ changes: [String: SettingChange]) throws
}

/// A group's settings on this device, and which of the shared ones it could hold: settings of an account this device
/// doesn't have are left for the devices that have it.
public struct LocalSettings: Equatable, Sendable {
    public var values: [String: Data]
    public var scope: Scope

    public enum Scope: Equatable, Sendable {
        case everything
        case only(Set<String>)

        public func covers(_ element: String) -> Bool {
            switch self {
            case .everything: true
            case .only(let elements): elements.contains(element)
            }
        }
    }

    public init(_ values: [String: Data], scope: Scope = .everything) {
        self.values = values
        self.scope = scope
    }
}
