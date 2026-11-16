import GmailProvider
import IMAPProvider
import MailCore
import MailNotifications
import MailStore
import OSLog
import OutlookProvider
import Synchronization
import UserNotifications
import os

/// Turns the relay's bare new-mail push into alerts for the mail it announced: catches the account up, alerts for
/// each new thread, and stores what it fetched for the app (ADR-002). A push that brings no new inbox mail, or whose
/// mail couldn't be fetched in time, never shows the push's bare "New mail" with a sound (`NewMailSilence`).
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
        guard let target = NewMailFetch.target(in: userInfo) else { return delivery.silence() }
        Task { @concurrent in
            do {
                let (fetch, pictures) = try Self.fetch()
                let outcome = try await fetch.run(target)
                do {
                    let badge = try fetch.badgeCount()
                    try await UNUserNotificationCenter.current().setBadgeCount(badge)
                    Logger.push.notice("Set the badge to \(badge, privacy: .public) after a push")
                } catch {
                    Logger.push.error("Couldn't set the badge after a push: \(error, privacy: .public)")
                }
                await delivery.finish(with: outcome, pictures: pictures)
            } catch {
                Logger.push.error("Couldn't fetch the new mail: \(error, privacy: .public)")
                delivery.silence()
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // The fetch may still be writing, and iOS suspends the extension next: holding a lock in the shared container
        // then gets it killed (0xdead10cc).
        MailDatabase.suspendAll()
        delivery.withLock { $0 }?.silence()
    }

    /// The fetch, and senders' pictures from the cache the app shares.
    private static func fetch() throws -> (NewMailFetch, SenderPictureSources) {
        guard let directory = SharedContainer.directoryURL else { throw CocoaError(.fileNoSuchFile) }
        let database = try MailDatabase(url: directory.appending(path: "Mail/mail.sqlite"))
        let pictures = SenderPictureSources(directory: directory.appending(path: "SenderPictures"), database: database)
        let fetch = NewMailFetch(database: database, notify: RuleNotification.post) { account in
            switch account.service {
            case .gmail: GmailClient(session: OAuthSession(accountID: account.id, client: .gmail, keychain: Keychain()))
            case .outlook:
                OutlookClient(
                    session: OAuthSession(accountID: account.id, client: .outlook, keychain: Keychain()),
                    index: database)
            case .icloud:
                IMAPClient(
                    accountID: account.id, settings: .icloud(email: account.email),
                    password: try ICloudSignIn(secrets: Keychain()).appPassword(for: account.id), index: database)
            case .imap:
                IMAPClient(
                    accountID: account.id, login: try IMAPSignIn(secrets: Keychain()).login(for: account.id),
                    index: database)
            }
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
                try? await UNUserNotificationCenter.current().add(request)
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
