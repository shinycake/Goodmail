#if DEBUG
    import Foundation

    /// A Darwin notification a UI test posts once it has set the window up, so what the app does for the test comes
    /// when the test is ready rather than after a guessed wait (`TestArrival`, `TestAlert`).
    enum TestTrigger: String {
        case arrival = "com.idanbirman.goodmail.test.arrival"
        case alert = "com.idanbirman.goodmail.test.alert"

        private static var actions: [TestTrigger: () -> Void] = [:]
        /// Names this app's observation to the notify center, which wants something to name it by.
        private static let observer = NSObject()

        /// Runs `action` each time the test posts this trigger, in place of what ran before.
        func onPost(_ action: @escaping () -> Void) {
            Self.actions[self] = action
            // Unsafe because the center takes raw pointers. Safe: the observer is a static object that lives as long
            // as the process, the center never dereferences it, and the callback reads only the name it is given.
            unsafe CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(Self.observer).toOpaque(),
                { _, _, name, _, _ in
                    guard let name, let trigger = TestTrigger(rawValue: name.rawValue as String) else { return }
                    // Darwin notifications come on the run loop of the thread that observed them, the main thread.
                    MainActor.assumeIsolated { TestTrigger.actions[trigger]?() }
                }, rawValue as CFString, nil, .deliverImmediately)
        }
    }
#endif
