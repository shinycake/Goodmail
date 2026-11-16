import UIKit

/// The accessibility settings the screens follow, and VoiceOver's announcements.
///
/// The only uses of `UIAccessibility`, which the SDK marks unsafe because it also declares pointer-taking C
/// functions. Reading a setting and posting a notification touch no memory of ours.
enum SystemAccessibility {
    static var reducesMotion: Bool { unsafe UIAccessibility.isReduceMotionEnabled }

    /// Tells VoiceOver about a change, as `UIAccessibility.post(notification:argument:)` does.
    static func post(_ notification: UIAccessibility.Notification, argument: Any? = nil) {
        unsafe UIAccessibility.post(notification: notification, argument: argument)
    }
}
