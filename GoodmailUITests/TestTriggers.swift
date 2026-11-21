import Foundation

/// Posts the app's `TestTrigger` named `name`, as `arrival` or `alert`, once a test has set the window up as it needs,
/// so what the trigger does comes when the test is ready rather than after a guessed wait.
func postTestTrigger(_ name: String) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName("com.idanbirman.goodmail.test.\(name)" as CFString),
        nil, nil, true)
}
