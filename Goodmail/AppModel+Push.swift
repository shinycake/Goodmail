import Foundation
import MailCore
import MailNotifications
import MailStore
import OSLog

/// Push subscriptions, alert choices, and what the reader does from an alert.
extension AppModel {
    /// Brings every push-capable account's subscription up to date. Cheap when nothing is due, so it runs on every
    /// activation.
    func refreshPush() async {
        guard let registrar = pushRegistrar, let device = pushDevice else { return }
        let sources = accounts.compactMap { account in
            pushSource(for: account.id).map { (account.id, $0) }
        }
        await withTaskGroup(of: Void.self) { group in
            for (id, source) in sources {
                group.addTask {
                    do {
                        try await registrar.refresh(id, source: source, device: device)
                    } catch {
                        Logger.push.error("Couldn't update push for an account: \(error, privacy: .public)")
                    }
                }
            }
        }
    }

    /// Takes this device off the relay for the account. A failure leaves a stale token, which the relay drops
    /// once APNs refuses it.
    func unsubscribePush(_ id: AccountID) async {
        guard let registrar = pushRegistrar, let source = pushSource(for: id) else { return }
        do {
            try await registrar.unsubscribe(id, source: source)
        } catch {
            Logger.push.error("Couldn't unregister push for an account: \(error, privacy: .public)")
        }
    }

    func notificationLevels() async -> [AccountID: NotificationLevel] {
        let (database, ids) = (database, accounts.map(\.id))
        return
            (try? await Self.offMain {
                Dictionary(
                    uniqueKeysWithValues: try ids.map { ($0, try database.notifications(for: $0, now: .now).level) })
            }) ?? [:]
    }

    func setNotificationLevel(_ level: NotificationLevel, for id: AccountID) async {
        let database = database
        do {
            try await Self.offMain { try database.setNotificationLevel(level, for: id, now: .now) }
        } catch {
            Logger.push.error("Couldn't store the alert choice: \(error, privacy: .public)")
        }
        await refreshPush()
    }

    /// Records the Inbox as seen while the app shows it, so mail read here never alerts later when its thread
    /// changes again.
    func markInboxSeen() async {
        let (database, ids) = (database, accounts.map(\.id))
        try? await Self.offMain {
            for id in ids {
                if let newest = try database.newestInboxDate(for: id) {
                    try database.markSeen(through: newest, for: id, now: .now)
                }
            }
        }
    }

    /// Applies an alert's action and sends it to the service before returning, since the app may be suspended
    /// straight after.
    func perform(_ action: ThreadAction, onAlerted thread: ThreadSummary.ID) async {
        do {
            _ = try await commands.perform(action, on: [thread])
        } catch {
            Logger.push.error("Couldn't apply an alert action: \(error, privacy: .public)")
        }
        await outboxes.flush(thread.accountID)
    }

    /// Sends `text` as a reply to the newest message in the thread, signed as the composer signs it, with the
    /// conversation quoted below.
    func reply(to thread: ThreadSummary.ID, with text: String) async throws {
        guard let account = accounts.first(where: { $0.id == thread.accountID }) else { return }
        let provider = try providers.provider(for: thread.accountID)
        let fetchedAt = Date.now
        let messages = try await provider.messages(inThread: thread.threadID)
        guard let latest = messages.last else { return }
        let database = database
        let signature = try await Self.offMain {
            try database.save(messages, inThread: thread, fetchedAt: fetchedAt)
            return try database.signature(for: account.id)
        }
        var plain = text
        if let signature, !signature.isEmpty { plain += "\n\n-- \n" + signature }
        // Each line its own `dir="auto"` block, as the composer writes it, so Hebrew replies read right to left.
        let html = plain.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? "<div><br></div>" : "<div dir=\"auto\">\(HTMLText.escape(String(line)))</div>"
        }
        var draft = Draft.reply(to: latest, all: false, accountEmail: account.email)
        draft.body = MessageBody(html: html.joined(), plain: plain)
        try await commands.send(draft, after: .zero)
    }

    private func pushSource(for id: AccountID) -> (any PushSource)? {
        guard accounts.first(where: { $0.id == id })?.service.pushesNewMail == true else { return nil }
        return (try? providers.provider(for: id)) as? any PushSource
    }

    /// Database work off the main actor: any write can wait out another process's lock (ADR-002).
    @concurrent static func offMain<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }
}

extension Logger {
    nonisolated static let push = Logger(subsystem: "com.idanbirman.goodmail", category: "push")
}
