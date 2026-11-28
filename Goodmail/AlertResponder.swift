import MailCore
import MailNotifications
import UserNotifications

/// Answers taps and actions on alerts from the moment the app launches: a tap that launched the app reaches the
/// delegate only if it is set before launch finishes, which can be before the database has opened. Each answer waits
/// for the push coordinator, and does nothing when the database couldn't open.
final class AlertResponder: NSObject {
    private let push: () async throws -> PushCoordinator

    init(push: @escaping () async throws -> PushCoordinator) {
        self.push = push
    }

    /// Call before launch finishes.
    func start() {
        UNUserNotificationCenter.current().delegate = self
    }
}

/// iOS calls these on its own queue, so they read what they need there and hop to the main actor to act on it.
/// They take iOS's completion handler rather than being `async`: the `async` forms hand iOS their result off the main
/// thread, where UIKit asserts while updating the app's snapshot. Each task ends by calling the handler, on every
/// path, so iOS owns it: iOS waits for the handler, and nothing else awaits or cancels the task.
extension AlertResponder: UNUserNotificationCenterDelegate {
    /// The reader is already in the app, where the new mail shows in the list: the alert goes straight to
    /// Notification Center.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let done = MainActorCompletion { completionHandler([.list]) }
        Task { @MainActor in done.call() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // The bare push, shown when the extension couldn't fetch, opens the app as it is.
        let thread = NewMailAlert.thread(in: response.notification.request.content.userInfo)
        let action = response.actionIdentifier
        let reply = (response as? UNTextInputNotificationResponse)?.userText
        let done = MainActorCompletion(completionHandler)
        Task { @MainActor in
            if let thread, let push = try? await push() {
                await BackgroundDatabaseWork.shared.run("Notification action") {
                    await push.answer(thread, action: action, reply: reply)
                }
            }
            done.call()
        }
    }
}
