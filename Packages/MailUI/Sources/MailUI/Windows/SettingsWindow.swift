public import Foundation

/// The one Settings window, where Settings opens in a window of its own (`SettingsPlacement.ownWindow`). The window
/// travels as this activity, so the system opens and restores it as Settings rather than as a mail window.
public enum SettingsWindow {
    /// The `NSUserActivity` type the window travels as, declared in the app's `NSUserActivityTypes`.
    public static let activityType = "com.idanbirman.goodmail.settings"

    public static var activity: NSUserActivity {
        NSUserActivity(activityType: activityType)
    }

    /// Whether `activity` opens or restores the Settings window.
    public static func opens(_ activity: NSUserActivity) -> Bool {
        activity.activityType == activityType
    }
}
