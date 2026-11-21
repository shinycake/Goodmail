import MailCore
import MailNotifications
import MailStore
import OSLog
import UIKit
import UserNotifications

/// The app's side of alerts: asks for permission once there is mail to alert for, hands the device token to the
/// model, and answers taps and actions on new-mail alerts.
final class PushCoordinator {
    private let model: AppModel
    /// Shows a tapped alert's thread in the frontmost window, or the first to connect.
    private let routes: IntentRoutes
    /// The latest update of the accounts' push subscriptions. A newer one replaces it, since it covers the same.
    private var update: Task<Void, Never>?
    /// Brings the subscriptions up to date on a timer where the app keeps running, for as long as this coordinator
    /// lives. `nil` where coming back to the app does it (`PresencePolicy.pushRenewalInterval`).
    private var renewal: Task<Void, Never>?
    /// The latest clearing of placeholder alerts.
    private var placeholders: Task<Void, Never>?
    /// Keeps the app badge on the unread count for the app's lifetime.
    private let badge: AppBadge
    /// Takes down alerts for mail the reader dealt with, for the app's lifetime.
    private let handled: HandledAlertsSweep

    /// Whether the reader is at the app, for what is done each time they come to it.
    private let presence: PresenceTracker

    init(model: AppModel, routes: IntentRoutes, presence: PresenceTracker) {
        self.model = model
        self.routes = routes
        self.presence = presence
        badge = AppBadge(database: model.database)
        handled = HandledAlertsSweep(database: model.database)
    }

    /// Call once, when the database has opened. `AlertResponder` answers the alerts from launch on, and hands them
    /// here.
    func start(_ application: UIApplication) {
        UNUserNotificationCenter.current().setNotificationCategories([NewMailAlert.category])
        badge.start(accounts: { [model] in model.accounts }, presence: presence)
        // Rules post alerts too, so this runs with or without a push relay.
        handled.start()
        guard model.pushRegistrar != nil else {
            Logger.push.notice("No push relay in this build; alerts are off")
            return
        }
        model.didAddAccount = { [weak self] in self?.updateSubscriptions() }
        application.registerForRemoteNotifications()
        presence.follow { [weak self] _, new in
            guard new == .attended else { return }
            self?.clearPlaceholders()
            self?.updateSubscriptions()
        }
        if presence.presence == .attended { clearPlaceholders() }
        updateSubscriptions()
        if let interval = presence.policy.pushRenewalInterval { renewal = renew(every: interval) }
    }

    isolated deinit {
        renewal?.cancel()
    }

    /// Brings the subscriptions up to date every `interval` until cancelled. A Mac app can run for days without the
    /// reader coming back to it, which is when the rest of the app brings them up to date.
    private func renew(every interval: Duration) -> Task<Void, Never> {
        Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                self?.updateSubscriptions()
            }
        }
    }

    func didRegister(deviceToken: Data) {
        model.pushDevice = DeviceToken(
            deviceToken, environment: PushConfiguration.environment, watch: AppModel.watchPushToken)
        updateSubscriptions()
    }

    /// The reader is looking at the mail, so pushes that showed only "New mail" have nothing left to say.
    private func clearPlaceholders() {
        placeholders?.cancel()
        placeholders = Task { await NewMailAlert.removePlaceholders() }
    }

    /// Asks for permission if it hasn't been asked, then brings every account's subscription up to date.
    private func updateSubscriptions() {
        update?.cancel()
        update = Task { [model, badge] in
            await badge.askForPermission()
            guard !Task.isCancelled else { return }
            await model.refreshPush()
        }
    }

    /// What the reader chose on an alert about `thread`.
    func answer(_ thread: ThreadSummary.ID, action: String, reply: String?) async {
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
