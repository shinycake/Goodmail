import Foundation
import MailClients
import MailCore
import MailStore

/// The Share extension's way to the mail the app keeps: the shared database (ADR-002), its accounts, and their
/// clients, built from the sign-ins in the shared Keychain. Everything here runs off the main actor.
nonisolated struct ShareSession: Sendable {
    /// What the writer asked for when the composer closed.
    enum Errand: Sendable {
        case send
        case saveDraft
        /// Send at a time the writer picked: the app sends it then, as any scheduled message.
        case schedule(Date)
    }

    /// How an errand ended.
    enum Ending: Sendable {
        /// Sent, saved or kept for the app (`ImmediateDelivery`).
        case delivered(ImmediateDelivery.Outcome)
        /// The account's sign-in isn't on this device, so the message waits in the app until the writer signs in.
        case waitingForSignIn
    }

    enum Failure: Error {
        /// The extension has no App Group, as in an unsigned build.
        case noSharedContainer
    }

    let database: MailDatabase
    /// The message as it is written, kept for the app in case the sheet goes away unasked.
    let drafts: ShareDrafts
    /// The accounts in the order the reader keeps them; the first is where a new message starts.
    let accounts: [Account]

    @concurrent static func open() async throws -> ShareSession {
        guard let directory = SharedContainer.directoryURL else { throw Failure.noSharedContainer }
        let database = try MailDatabase(url: directory.appending(path: "Mail/mail.sqlite"))
        return ShareSession(
            database: database, drafts: ShareDrafts(database: database), accounts: try database.accounts())
    }

    /// Carries out `errand` for `draft`. A message to send or a draft to save goes now, from here; what can't
    /// finish waits in the shared queue for the app (`ImmediateDelivery`), as does a message whose account has no
    /// sign-in on this device, which goes once the writer signs in again in the app. Throws
    /// `ImmediateDelivery.NotKept` when the message couldn't be kept anywhere.
    @concurrent func run(_ errand: Errand, for draft: Draft) async throws -> Ending {
        // The errand takes the place of the version kept as it was written.
        await drafts.settle()
        drafts.take(draft.id)
        let purpose: OutgoingMessage.Purpose
        switch errand {
        case .send: purpose = .send
        case .saveDraft: purpose = .saveDraft
        case .schedule(let date):
            try keep(OutgoingMessage(draft: draft, purpose: .scheduledSend, sendAt: date))
            return .delivered(.handedOver(.queued))
        }
        // The accounts come from this database, so the draft's is always among them.
        let account = accounts.first { $0.id == draft.accountID }
        guard let provider = try? account.map({ try MailClients.client(for: $0, index: database) }) else {
            try keep(OutgoingMessage(draft: draft, purpose: purpose, sendAt: .now))
            return .waitingForSignIn
        }
        let delivery = ImmediateDelivery(
            draft, as: purpose, provider: provider, store: database,
            scratch: FileManager.default.temporaryDirectory.appending(path: "Uploads", directoryHint: .isDirectory))
        return .delivered(try await Self.awake(whileRunning: delivery))
    }

    private func keep(_ message: OutgoingMessage) throws {
        do {
            try database.enqueue(message)
        } catch {
            throw ImmediateDelivery.NotKept(mayHaveGone: false)
        }
    }

    /// Runs `delivery` with the time iOS gives a process to finish when it leaves the screen, as the extension does
    /// with its host app. When that runs out first, what's left goes to the app before iOS suspends the extension.
    ///
    /// iOS asks for the activity's end on a queue of its own, by the block returning: the first call holds its
    /// thread until the delivery is done, which is how `performExpiringActivity` is meant to be used. It never runs
    /// on the cooperative pool.
    private static func awake(whileRunning delivery: ImmediateDelivery) async throws -> ImmediateDelivery.Outcome {
        let done = DispatchSemaphore(value: 0)
        defer { done.signal() }
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Sending a shared message") { expired in
            if expired {
                _ = try? delivery.handOver()
            } else {
                done.wait()
            }
        }
        return try await delivery.run()
    }
}
