#if DEBUG
    import UIKit

    /// `-GoodmailFastAnimations YES` runs every animation in the app's windows ten times faster, so a UI test that
    /// only waits for an animation to end spends a tenth of the time on it. Each window speeds up as it becomes
    /// visible, compose and Settings windows and the keyboard's included. Tests that check an animation's frames, or
    /// time a gesture against one, leave it off (`AnimationSpeed` in GoodmailUITests).
    enum TestAnimations {
        private static let speed: Float = 10
        /// Kept for the app's lifetime: the observation ends with its token, and the speed-up never turns off once on.
        private static var observation: NotificationCenter.ObservationToken?

        /// Call once, from `AppLaunch.start()`, before any window shows.
        static func startIfRequested() {
            guard UserDefaults.standard.bool(forKey: "GoodmailFastAnimations") else { return }
            // A main actor message: UIKit posts it on the main thread as the window becomes visible.
            observation = NotificationCenter.default.addObserver(of: UIWindow.self, for: .didBecomeVisible) { message in
                message.window.layer.speed = speed
            }
        }
    }
#endif
