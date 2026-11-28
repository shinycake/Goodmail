import MailClients
import MailCore
import MailNotifications
import MailStore
import OSLog
import Synchronization
import UserNotifications
import os

/// Turns the relay's new-mail push into alerts for the mail it announced: catches the account up, alerts for each new
/// thread with the sender's picture and a preview, and stores what it fetched for the app (ADR-002). The relay only
/// sends a push it has read the email for, with its sender and subject (PushWorker/README.md), so a push whose mail
/// can't be fetched in time shows as the relay sent it. One whose mail the app doesn't alert for here (already
/// alerted, muted, or out of Focus) shows quietly (`NewMailSilence`).
final class NotificationService: UNNotificationServiceExtension {
    private let delivery = Mutex<Delivery?>(nil)

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let silence = NewMailSilence(info: Bundle.main.infoDictionary)
        let delivery = Delivery(push: request.content, silence: silence, handler: contentHandler)
        self.delivery.withLock { $0 = delivery }
        let userInfo = request.content.userInfo
        let target = NewMailFetch.target(in: userInfo)
        let receipt = AlertReceipt.id(in: userInfo)
        // A bridge from iOS's callback, which nothing awaits: iOS keeps the extension running until `delivery` hands
        // over the alert, which it does exactly once, from here or from `serviceExtensionTimeWillExpire`, and the
        // task's failures end in `delivery` and the log. Whatever the task does after the deadline goes nowhere.
        Task { @concurrent in
            // Beside the fetch, which can take most of the 8 seconds before the relay alerts the watch instead.
            async let confirmed: Void = Self.confirm(receipt)
            if let target { await Self.alert(target, through: delivery) } else { delivery.silence() }
            await confirmed
        }
    }

    /// Catches the account up and hands iOS the alert for the mail `target` announced.
    @concurrent private static func alert(_ target: NewMailFetch.Target, through delivery: Delivery) async {
        do {
            let (fetch, pictures) = try Self.fetch()
            let outcome = try await fetch.run(target)
            do {
                let badge = try await fetch.badgeCount()
                try await UNUserNotificationCenter.current().setBadgeCount(badge)
                Logger.push.notice("Set the badge to \(badge, privacy: .public) after a push")
            } catch {
                Logger.push.error("Couldn't set the badge after a push: \(error, privacy: .private)")
            }
            // The catch-up also brought what was read, filed or deleted since, here or anywhere else.
            await fetch.dismissHandledAlerts()
            await delivery.finish(with: outcome, pictures: pictures)
        } catch {
            Logger.push.error("Couldn't fetch the new mail: \(error, privacy: .private)")
            delivery.asSent()
        }
    }

    /// Tells the relay this iPhone has the alert, so it doesn't send it to the watch as well (ADR-023). A failure
    /// costs only a second alert on the watch.
    @concurrent private static func confirm(_ receipt: String?) async {
        guard let receipt, let relay else { return }
        do {
            try await relay.acknowledge(alert: receipt)
        } catch {
            Logger.push.error("Couldn't confirm an alert to the relay: \(error, privacy: .private)")
        }
    }

    /// The relay this build registers with, from the `GOODMAIL_PUSH_RELAY_URL` build setting the app reads too.
    private static let relay: PushRelayClient? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GoodmailPushRelayURL") as? String,
            let url = URL(string: value), !value.isEmpty
        else { return nil }
        return PushRelayClient(baseURL: url)
    }()

    override func serviceExtensionTimeWillExpire() {
        // The fetch may still be writing, and iOS suspends the extension next: holding a lock in the shared container
        // then gets it killed (0xdead10cc).
        MailDatabase.suspendAll()
        delivery.withLock { $0 }?.asSent()
    }

    /// The fetch, and senders' pictures from the cache the app shares.
    private static func fetch() throws -> (NewMailFetch, SenderPictureSources) {
        guard let directory = SharedContainer.directoryURL else { throw CocoaError(.fileNoSuchFile) }
        let database = try MailDatabase(url: directory.appending(path: "Mail/mail.sqlite"))
        let pictures = SenderPictureSources(directory: directory.appending(path: "SenderPictures"), database: database)
        let fetch = NewMailFetch(database: database, notify: RuleNotification.post) { account in
            try MailClients.client(for: account, index: database)
        }
        return (fetch, pictures)
    }
}

/// Hands iOS one alert per push, exactly once: the fetched mail's, or the push's silence. The fetch and iOS's
/// deadline race to it.
///
/// `@unchecked Sendable` because iOS's handler and content types aren't `Sendable`. Safe: every access to them is
/// under `state`'s lock, the push is never mutated, and the handler runs at most once.
private final class Delivery: @unchecked Sendable {
    private enum State {
        /// The push as it came, which the silence is made from, and where to hand the alert.
        case waiting(push: UNNotificationContent, handler: (UNNotificationContent) -> Void)
        case delivered
    }

    private let state: OSAllocatedUnfairLock<State>
    private let silenceKind: NewMailSilence

    init(push: UNNotificationContent, silence: NewMailSilence, handler: @escaping (UNNotificationContent) -> Void) {
        state = OSAllocatedUnfairLock(uncheckedState: .waiting(push: push, handler: handler))
        silenceKind = silence
    }

    func finish(with outcome: NewMailFetch.Outcome, pictures: SenderPictureSources) async {
        switch outcome {
        case .alerts(let mail, let account):
            guard let newest = mail.first else { return silence() }
            // The push shows the newest; each other thread gets its own alert, posted before the push's lands.
            for other in mail.dropFirst() {
                let content = await SenderAlert.content(for: other, in: account, pictures: pictures)
                let request = UNNotificationRequest(
                    identifier: NewMailAlert.identifier(for: other.thread.id), content: content, trigger: nil)
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    // The push's alert still shows the newest; this thread waits for the next push or the app.
                    Logger.push.error("Couldn't post the alert for a new thread: \(error, privacy: .private)")
                }
            }
            let alert = await SenderAlert.content(for: newest, in: account, pictures: pictures)
            deliver { _ in alert }
        case .nothingNew:
            // One placeholder at a time: this one replaces any left from earlier pushes.
            if silenceKind == .quiet { await NewMailAlert.removePlaceholders() }
            silence()
        }
    }

    /// Hands iOS the push's silence, unless an alert was already handed over.
    func silence() {
        deliver(silenceKind.content(for:))
    }

    /// Hands iOS the push as the relay sent it, with the email's sender and subject, unless an alert was already
    /// handed over.
    func asSent() {
        deliver { $0 }
    }

    /// Hands iOS `content` made from the push as it came.
    private func deliver(_ content: (UNNotificationContent) -> UNNotificationContent) {
        state.withLockUnchecked { state in
            guard case .waiting(let push, let handler) = state else { return }
            state = .delivered
            handler(content(push))
        }
    }
}

extension Logger {
    fileprivate static let push = Logger(subsystem: "com.idanbirman.goodmail", category: "push")
}
