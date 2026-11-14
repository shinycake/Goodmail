import GmailProvider
import MailCore
import MailNotifications
import MailStore
import OSLog
import Synchronization
import UserNotifications
import os

/// Turns the relay's bare new-mail push into alerts for the mail it announced: catches the account up, alerts for
/// each new thread, and stores what it fetched for the app (ADR-002).
final class NotificationService: UNNotificationServiceExtension {
    private let delivery = Mutex<Delivery?>(nil)

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let delivery = Delivery(fallback: request.content, handler: contentHandler)
        self.delivery.withLock { $0 = delivery }
        let userInfo = request.content.userInfo
        guard let address = NewMailFetch.address(in: userInfo) else { return delivery.expire() }
        Task { @concurrent in
            do {
                let fetch = try Self.fetch()
                let outcome = try await fetch.run(address: address)
                if let badge = try? fetch.badgeCount() {
                    try? await UNUserNotificationCenter.current().setBadgeCount(badge)
                }
                await delivery.finish(with: outcome)
            } catch {
                Logger.push.error("Couldn't fetch the new mail: \(error, privacy: .public)")
                delivery.expire()
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        delivery.withLock { $0 }?.expire()
    }

    private static func fetch() throws -> NewMailFetch {
        guard let directory = SharedContainer.directoryURL else { throw CocoaError(.fileNoSuchFile) }
        let database = try MailDatabase(url: directory.appending(path: "Mail/mail.sqlite"))
        return NewMailFetch(database: database) { account in
            switch account.service {
            case .gmail: GmailClient(session: OAuthSession(accountID: account.id, client: .gmail, keychain: Keychain()))
            // Only Gmail goes through the relay so far.
            case .icloud, .outlook: throw NewMailFetch.Failure.unknownAccount
            }
        }
    }
}

/// Hands iOS one alert per push, exactly once: the fetched mail's, nothing, or the push as it came. The fetch and
/// iOS's deadline race to it.
///
/// `@unchecked Sendable` because iOS's handler and content types aren't `Sendable`. Safe: every access to them is
/// under `state`'s lock, the fallback is never mutated, and the handler runs at most once.
private final class Delivery: @unchecked Sendable {
    private enum State {
        /// The push as it came, shown if nothing better is ready in time, and where to hand the alert.
        case waiting(fallback: UNNotificationContent, handler: (UNNotificationContent) -> Void)
        case delivered
    }

    private let state: OSAllocatedUnfairLock<State>

    init(fallback: UNNotificationContent, handler: @escaping (UNNotificationContent) -> Void) {
        state = OSAllocatedUnfairLock(uncheckedState: .waiting(fallback: fallback, handler: handler))
    }

    func finish(with outcome: NewMailFetch.Outcome) async {
        switch outcome {
        case .alerts(let threads, let account):
            guard let newest = threads.first else { return expire() }
            let logos = SharedContainer.directoryURL.map { SenderLogos(directory: $0.appending(path: "SenderLogos")) }
            // The push shows the newest; each other thread gets its own alert, posted before the push's lands.
            for thread in threads.dropFirst() {
                let content = await SenderAlert.content(for: thread, in: account, logos: logos)
                let request = UNNotificationRequest(
                    identifier: NewMailAlert.identifier(for: thread.id), content: content, trigger: nil)
                try? await UNUserNotificationCenter.current().add(request)
            }
            deliver(await SenderAlert.content(for: newest, in: account, logos: logos))
        case .nothingNew:
            // Empty content drops the alert, with the filtering entitlement; without it iOS shows the push as it came.
            deliver(UNNotificationContent())
        }
    }

    /// Shows the push as it came, whose text stands on its own, unless an alert was already handed over.
    func expire() {
        deliver(nil)
    }

    /// `nil` hands over the push as it came.
    private func deliver(_ content: UNNotificationContent?) {
        state.withLockUnchecked { state in
            guard case .waiting(let fallback, let handler) = state else { return }
            state = .delivered
            handler(content ?? fallback)
        }
    }
}

extension Logger {
    fileprivate static let push = Logger(subsystem: "com.idanbirman.goodmail", category: "push")
}
