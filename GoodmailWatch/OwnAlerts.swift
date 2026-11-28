import Foundation
import MailCore
import MailWrist
import OSLog
import Observation
import UserNotifications
import WatchKit

/// The alerts the push relay sends the watch itself when the iPhone doesn't confirm one in time (ADR-023). The watch
/// registers for remote notifications and hands its token to the iPhone, which registers it with the relay beside its
/// own; the watch never talks to the relay.
final class OwnAlerts {
    nonisolated static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "own-alerts")

    /// What reaches the token's way to the iPhone.
    private enum Event {
        /// APNs gave the watch a token.
        case token(Data)
        /// The link to the iPhone came up.
        case linkReady
    }

    private let channel: WristChannel
    private let events: AsyncStream<Event>
    private let eventsIn: AsyncStream<Event>.Continuation

    init(channel: WristChannel) {
        self.channel = channel
        (events, eventsIn) = AsyncStream.makeStream(of: Event.self)
    }

    /// Runs for the app's lifetime: asks to show alerts, registers for them, and sends the iPhone the latest token
    /// APNs gave this launch, at once and again each time the link comes up. APNs hands it over at every launch.
    func run() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.error("Couldn't ask to show alerts: \(error, privacy: .private)")
        }
        WKApplication.shared().registerForRemoteNotifications()
        var latest: Data?
        for await event in events {
            switch event {
            case .token(let token):
                latest = token
                await channel.send(pushToken: token)
            case .linkReady:
                if let latest { await channel.send(pushToken: latest) }
            }
        }
    }

    /// Runs for the app's lifetime: each time the Inbox the watch holds changes, takes down the alerts the relay sent
    /// the watch whose mail the reader has dealt with since (`WristMailbox.handledAlerts`). Alerts mirrored from the
    /// iPhone come down with the iPhone's.
    static func takeDownHandled(following inbox: WristInboxModel) async {
        for await mailbox in Observations({ inbox.mailbox }) {
            await takeDownHandled(in: mailbox)
        }
    }

    /// Reads Notification Center off the main actor, and removes what `mailbox` says was dealt with.
    @concurrent private static func takeDownHandled(in mailbox: WristMailbox) async {
        let center = UNUserNotificationCenter.current()
        // The relay's own pushes carry its payload, `aps` and all; mirrored alerts carry only the thread.
        let alerts = await center.deliveredNotifications().compactMap { notification -> WristDeliveredAlert? in
            let userInfo = notification.request.content.userInfo
            guard userInfo["aps"] != nil else { return nil }
            return WristDeliveredAlert(
                identifier: notification.request.identifier, payload: TappedAlert(userInfo).strings,
                deliveredAt: notification.date)
        }
        let handled = mailbox.handledAlerts(alerts)
        guard !handled.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: handled)
        log.notice("Took down \(handled.count, privacy: .public) alerts for mail dealt with")
    }

    func received(token: Data) {
        eventsIn.yield(.token(token))
    }

    func linkReady() {
        eventsIn.yield(.linkReady)
    }

    /// Opens what a tapped alert is about: the conversation of an alert mirrored from the iPhone, or the target of
    /// one the relay sent the watch, which is the conversation when the watch reads its account itself and the Inbox
    /// otherwise.
    static func open(_ alert: TappedAlert, inbox: WristInboxModel, route: WristRoute) {
        if let thread = alert.mirroredThread { return route.open(thread) }
        // `inbox` is restored, so a tap that launched the app finds the accounts and their sources.
        switch WristAlertTarget(
            payload: alert.payload, accounts: inbox.mailbox.snapshot?.accounts ?? [],
            sources: inbox.mailbox.sources)
        {
        case .inbox: route.path = []
        case .thread(let thread): route.open(thread)
        }
    }

    static func didFailToRegister(_ error: any Error) {
        log.error("Couldn't register for the watch's own alerts: \(error, privacy: .private)")
    }
}

/// What a tapped alert carries, read where watchOS hands it over and sent on to the main actor.
nonisolated struct TappedAlert: Sendable {
    /// The thread of an alert mirrored from the iPhone.
    let mirroredThread: ThreadSummary.ID?
    /// The relay's payload, its string values only, which are all `WristAlertTarget` reads.
    let strings: [String: String]

    init(_ userInfo: [AnyHashable: Any]) {
        mirroredThread = AlertedThread.thread(in: userInfo)
        var strings: [String: String] = [:]
        for case (let key as String, let value as String) in userInfo { strings[key] = value }
        self.strings = strings
    }

    var payload: [AnyHashable: Any] { strings }
}

extension WatchAppDelegate {
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        alerts.received(token: deviceToken)
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: any Error) {
        OwnAlerts.didFailToRegister(error)
    }
}

/// watchOS calls these on its own queue, so they read the alert there and hop to the main actor to act on it. They
/// take watchOS's completion handler rather than being `async`: the `async` forms call it wherever their body
/// finishes, a cooperative thread for these `nonisolated` methods, where UIKit asserts and the app aborts on every
/// tap of an alert. Each task ends by calling the handler, so watchOS owns it: it waits for the handler, and
/// nothing else awaits or cancels the task.
extension WatchAppDelegate: UNUserNotificationCenterDelegate {
    /// An alert that arrives while the app is open shows anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let done = MainActorCompletion { completionHandler([.banner, .list, .sound]) }
        Task { @MainActor in done.call() }
    }

    /// A tap opens what the alert is about; an action runs before the handler is called, so the system doesn't
    /// suspend the app halfway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let alert = TappedAlert(response.notification.request.content.userInfo)
        let action = WristAlertAction(rawValue: response.actionIdentifier)
        let isTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        let done = MainActorCompletion(completionHandler)
        Task { @MainActor in
            if let action {
                await act(action, on: alert, text: text)
            } else if isTap {
                OwnAlerts.open(alert, inbox: await restoredInbox(), route: route)
            }
            done.call()
        }
    }
}
