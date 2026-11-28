import Foundation
import MailCore
import MailStore
public import MailWrist

#if canImport(OSLog)
    import OSLog
#endif

extension WristOwnHost {
    /// What the watch gives back when the switch goes off (ADR-023).
    public enum Handback: Codable, Equatable, Sendable {
        /// A change the reader made that hadn't reached the service: the iPhone makes it instead.
        case run(WristCommand)
        /// A reply the service turned down: it is taken back, for the reader to send again or let go.
        case undelivered(WristCommand)
        /// A reply whose upload never answered, which the service couldn't be asked about: it is taken back, though
        /// it may have gone.
        case unconfirmed(WristCommand)
    }

    /// Takes what the watch gives back, in the order the reader made it, and returns only once it has kept it for
    /// good: the watch lets go of it then. Throwing leaves it with the watch, to give back the next time. It may be
    /// given the same again, after the app was quit before the watch let go.
    public typealias Receiver = @Sendable ([Handback]) async throws -> Void

    /// Gives back what the reader's changes left undone, as the database has it, so that a change made before the app
    /// was quit is given back too. Each reply whose upload went unheard is asked about first, through `served` or a
    /// sender of its own. The handbacks are kept, the changes let go of and the copy forgotten in one transaction, so
    /// nothing given back can still go from the watch; then they are delivered (`redeliver`). Runs only while no
    /// check or change does. Throws when the database failed or `handBack` didn't take them; what was kept stays.
    func settle(served: [AccountID: Served] = [:]) async throws {
        try await redeliver()
        let kept = try database.watchChanges()
        // In the order the reader made them.
        let changes = kept.enumerated().compactMap { position, change -> (WristCommand, WatchChange, Int)? in
            do {
                return (try JSONDecoder().decode(WristCommand.self, from: change.command), change, position)
            } catch {
                Self.note("Let go of a change the watch couldn't read: \(error)")
                return nil
            }
        }.sorted { ($0.0.madeAt, $0.2) < ($1.0.madeAt, $1.2) }
        let replying = Set(changes.filter { !$0.1.drafts.isEmpty }.flatMap { $0.0.threads.map(\.accountID) })
        for account in replying { await settleUploads(of: account, served: served[account]) }
        var handbacks: [Handback] = []
        for (command, change, _) in changes {
            if let handback = try await handback(for: command, change) { handbacks.append(handback) }
        }
        let encoder = JSONEncoder()
        try database.handOver(try handbacks.map { try encoder.encode($0) }, changes: kept.map(\.id))
        try await redeliver()
    }

    /// Delivers what a handover kept and hasn't delivered yet, as after the app was quit in between.
    func redeliver() async throws {
        let kept = try database.watchHandbacks()
        guard !kept.isEmpty else { return }
        let handbacks = kept.compactMap { kept -> Handback? in
            do {
                return try JSONDecoder().decode(Handback.self, from: kept.handback)
            } catch {
                Self.note("Let go of a handback the watch couldn't read: \(error)")
                return nil
            }
        }
        if !handbacks.isEmpty { try await handBack(handbacks) }
        try database.removeWatchHandbacks(kept.map(\.position))
    }

    /// What to give back for `command`, kept as `change`: `nil` once nothing of it is on its way.
    private func handback(for command: WristCommand, _ change: WatchChange) async throws -> Handback? {
        guard case .reply = command.kind else { return change.queued ? .run(command) : nil }
        var deliveries: [OutgoingMessage.Delivery] = []
        for thread in command.threads {
            for message in try await database.firstValue(of: database.outgoingMessages(inThread: thread))
            where change.drafts.contains(message.draft.id) {
                deliveries.append(message.delivery)
            }
        }
        if deliveries.contains(where: { if case .uploading = $0 { true } else { false } }) {
            return .unconfirmed(command)
        }
        if deliveries.contains(where: { if case .failed = $0 { true } else { false } }) { return .undelivered(command) }
        return deliveries.isEmpty ? nil : .run(command)
    }

    /// Asks `account`'s service whether each of its replies whose upload went unheard went, without sending anything,
    /// through `served`, or a sender made for it when the account isn't served, from the account as the database
    /// keeps it: at a launch with the switch off, no account has been followed yet.
    private func settleUploads(of account: AccountID, served: Served?) async {
        let accounts: [Account]
        do {
            accounts = try database.accounts()
        } catch {
            // Unless the account is served, its uploads wait for the next time it is.
            Self.log.error("Couldn't read the accounts to settle an account's uploads", error)
            accounts = []
        }
        let stored = accounts.first { $0.id == account }.map { stored in
            WristAccount(
                id: stored.id, address: stored.email, color: stored.color, unread: 0, service: stored.service)
        }
        guard let served = served ?? stored.flatMap(makeServed) else { return }
        // Its sender only asks; nothing else of it runs, so nothing of it needs stopping.
        for (id, outcome) in uploads.takeOutcomes(of: account) { _ = await served.sender.complete(id, with: outcome) }
        await served.sender.settle()
    }

    /// Logs `message` where the platform keeps a log.
    private static func note(_ message: String) {
        #if canImport(OSLog)
            Logger(subsystem: "com.idanbirman.goodmail", category: "own-mail").error("\(message, privacy: .public)")
        #endif
    }
}
