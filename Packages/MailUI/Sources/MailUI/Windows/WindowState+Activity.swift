public import Foundation
public import MailCore

extension WindowState {
    /// The state as an activity, which restores a window, hands it off to another device, or opens a new window, as
    /// a thread dragged out of the list does.
    public var activity: NSUserActivity? {
        guard let saved = try? saved() else { return nil }
        let activity = NSUserActivity(activityType: Self.activityType)
        activity.userInfo = [Self.activityKey: saved]
        activity.isEligibleForHandoff = true
        return activity
    }

    /// The state `activity` carries, or `nil` for any other activity, or one a later build saved.
    public init?(_ activity: NSUserActivity) {
        guard activity.activityType == Self.activityType,
            let saved = activity.userInfo?[Self.activityKey] as? Data,
            let state = try? WindowState(saved: saved)
        else { return nil }
        self = state
    }
}
