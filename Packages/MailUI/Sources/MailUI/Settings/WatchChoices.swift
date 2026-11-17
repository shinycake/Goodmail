public import Foundation
public import Observation

/// The owner's Apple Watch choice (ADR-023): whether the watch reads Gmail and Outlook itself, so it keeps working
/// with the iPhone off or out of reach. Kept on this iPhone, which tells the watch with each Inbox it sends.
@MainActor @Observable
public final class WatchChoices {
    private nonisolated static let key = "mailWithoutIPhone"

    /// On unless the owner turned it off. Readable from anywhere, as the snapshots for the watch are made off the main
    /// actor.
    public nonisolated static var mailWithoutIPhone: Bool { mailWithoutIPhone(in: .standard) }

    nonisolated static func mailWithoutIPhone(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public var mailWithoutIPhone: Bool {
        didSet {
            guard mailWithoutIPhone != oldValue else { return }
            defaults.set(mailWithoutIPhone, forKey: Self.key)
            changed()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Runs after each change, for the app to tell the watch.
    @ObservationIgnored private let changed: () -> Void

    public init(defaults: UserDefaults = .standard, changed: @escaping () -> Void) {
        mailWithoutIPhone = Self.mailWithoutIPhone(in: defaults)
        self.defaults = defaults
        self.changed = changed
    }
}
