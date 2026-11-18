public import Foundation
public import MailCore

/// A window that holds one message being written, as when a message moves out of its window into one of its own on
/// iPad. The message itself is kept with the minimized messages under `key`, which outlasts the window: the
/// window reads it back when it opens or is restored, and a window put away for good leaves it there for the next
/// window to take as minimized.
public struct ComposeWindow: Equatable, Sendable {
    /// The `NSUserActivity` type the window travels as, declared in the app's `NSUserActivityTypes`.
    public static let activityType = "com.idanbirman.goodmail.compose"
    private static let keyKey = "window"

    /// Names the window's message among the minimized messages.
    public let key: String

    /// The window for `draft`, named after it, so the same message always has the same window.
    public init(for draft: Draft.ID) {
        key = "compose-\(draft.uuidString)"
    }

    /// The window `activity` opens or restores, or `nil` for any other activity.
    public init?(_ activity: NSUserActivity) {
        guard activity.activityType == Self.activityType, let key = activity.userInfo?[Self.keyKey] as? String
        else { return nil }
        self.key = key
    }

    public var activity: NSUserActivity {
        let activity = NSUserActivity(activityType: Self.activityType)
        activity.userInfo = [Self.keyKey: key]
        return activity
    }
}
