import MailCore
import MailNotifications
import MailStore
import OSLog
import UIKit
import UserNotifications

/// The app's side of alerts: asks for permission once there is mail to alert for, hands the device token to the
/// model, and answers taps and actions on new-mail alerts.
final class PushCoordinator: NSObject {
    private let model: AppModel
    /// Shows a tapped alert's thread in the frontmost window, or the first to connect.
    private let routes: IntentRoutes
    /// The latest update of the accounts' push subscriptions. A newer one replaces it, since it covers the same.
    private var update: Task<Void, Never>?
    /// Keeps the app badge on the unread count for the app's lifetime.
    private var badge: Task<Void, Never>?

    init(model: AppModel, routes: IntentRoutes) {
        self.model = model
        self.routes = routes
    }

    /// Call before launch finishes, so a tap that launched the app reaches the delegate.
    func start(_ application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([NewMailAlert.category])
        followBadgeCount()
        guard model.pushRegistrar != nil else {
            Logger.push.notice("No push relay in this build; alerts are off")
            return
        }
        model.didAddAccount = { [weak self] in self?.updateSubscriptions() }
        application.registerForRemoteNotifications()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSubscriptions() }
        }
        updateSubscriptions()
    }

    func didRegister(deviceToken: Data) {
        model.pushDevice = DeviceToken(deviceToken, environment: PushConfiguration.environment)
        updateSubscriptions()
    }

    /// Sets the badge whenever the count changes, here or in the notification extension. iOS shows it only when the
    /// reader allows badges.
    private func followBadgeCount() {
        badge = Task { [database = model.database] in
            do {
                for try await count in database.badgeCounts() {
                    try? await UNUserNotificationCenter.current().setBadgeCount(count)
                }
            } catch {
                Logger.push.error("Stopped updating the badge: \(error, privacy: .public)")
            }
        }
    }

    /// Asks for permission if it hasn't been asked, then brings every account's subscription up to date.
    private func updateSubscriptions() {
        update?.cancel()
        update = Task { [model] in
            await Self.requestAuthorization(for: model.accounts)
            guard !Task.isCancelled else { return }
            await model.refreshPush()
        }
    }

    /// Asks once, and only when there is an account whose mail could alert: asking on first launch, before the
    /// reader has added one, has nothing to explain it.
    private static func requestAuthorization(for accounts: [Account]) async {
        guard accounts.contains(where: \.service.pushesNewMail) else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Logger.push.error("Couldn't ask for alerts: \(error, privacy: .public)")
        }
    }

    /// What the reader chose on an alert about `thread`.
    private func answer(_ thread: ThreadSummary.ID, action: String, reply: String?) async {
        if action == UNNotificationDefaultActionIdentifier {
            routes.open(.thread(thread, in: .inbox))
            return
        }
        switch NewMailAlert.Action(rawValue: action) {
        case .reply:
            guard let reply, !reply.isEmpty else { return }
            do {
                try await model.reply(to: thread, with: reply)
            } catch {
                Logger.push.error("Couldn't send the reply from an alert: \(error, privacy: .public)")
            }
        case .markRead: await model.perform(.markRead(true), onAlerted: thread)
        case .archive: await model.perform(.archive, onAlerted: thread)
        case .trash: await model.perform(.trash, onAlerted: thread)
        case nil: break
        }
    }
}

/// iOS calls these on its own queue, so they read what they need there and hop to the main actor to act on it.
/// They take iOS's completion handler rather than being `async`: the `async` forms hand iOS their result off the main
/// thread, where UIKit asserts while updating the app's snapshot.
extension PushCoordinator: UNUserNotificationCenterDelegate {
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
            if let thread { await answer(thread, action: action, reply: reply) }
            done.call()
        }
    }
}

/// iOS's completion handler, carried to the main actor and called there once the answer is done.
///
/// `@unchecked Sendable` because the handler's type isn't `Sendable`. Safe: it is created on iOS's queue, never
/// touched there again, and called only on the main actor, once.
nonisolated private struct MainActorCompletion: @unchecked Sendable {
    let call: () -> Void

    init(_ call: @escaping () -> Void) {
        self.call = call
    }
}
