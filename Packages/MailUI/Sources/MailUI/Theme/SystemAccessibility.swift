import UIKit

/// The accessibility settings the screens follow, and VoiceOver's announcements.
///
/// The only uses of `UIAccessibility`, which the SDK marks unsafe because it also declares pointer-taking C
/// functions. Reading a setting and posting a notification touch no memory of ours.
enum SystemAccessibility {
    static var reducesMotion: Bool { unsafe UIAccessibility.isReduceMotionEnabled }

    /// Whether VoiceOver or Switch Control runs, which move through the screen one element at a time and take
    /// longer to reach a control than a finger does.
    static var assistiveTechnologyRuns: Bool {
        unsafe UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    /// Has VoiceOver say `text`. A `queued` announcement waits for what VoiceOver is saying, such as the letter just
    /// typed, instead of cutting it off.
    static func announce(_ text: String, queued: Bool = false) {
        let speech = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: queued])
        post(.announcement, argument: speech)
    }

    /// `rect`, in `view`'s coordinates, in the screen's, where accessibility frames are.
    static func screenFrame(of rect: CGRect, in view: UIView) -> CGRect {
        unsafe UIAccessibility.convertToScreenCoordinates(rect, in: view)
    }

    /// Tells VoiceOver about a change, as `UIAccessibility.post(notification:argument:)` does.
    static func post(_ notification: UIAccessibility.Notification, argument: Any? = nil) {
        unsafe UIAccessibility.post(notification: notification, argument: argument)
    }
}
