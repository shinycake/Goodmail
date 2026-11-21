import Foundation
public import MailCore

extension Preferences {
    /// What opens after the reader archives, deletes, moves, snoozes or mutes the conversation they're reading. Read
    /// at each action, so a change applies to the next one.
    public static var afterRemoval: AfterRemoval {
        get { AfterRemoval(stored: defaults.string(forKey: afterRemovalKey)) }
        set { defaults.set(newValue.rawValue, forKey: afterRemovalKey) }
    }

    nonisolated static let afterRemovalKey = "afterRemoval"
}
