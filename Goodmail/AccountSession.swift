import MailCore
import OSLog

/// One account's live objects, all made on the same provider: what syncs it and prefetches its bodies. `Providers`
/// keeps one per account and replaces it whole when the account signs in afresh, so none goes on with an old
/// password, server or token. The outbox (`Outboxes`) and sending (`Senders`) stay one per account for the launch, so
/// their drains never overlap, and read the session's provider as each one begins; the IMAP watch (`ChangeWatchers`)
/// follows the session it was made on.
nonisolated final class AccountSession: LiveSession {
    let provider: any MailProvider
    let engine: SyncEngine
    let prefetcher: BodyPrefetcher

    init(provider: any MailProvider, engine: SyncEngine, prefetcher: BodyPrefetcher) {
        self.provider = provider
        self.engine = engine
        self.prefetcher = prefetcher
    }

    /// A sync under way finishes on the old provider, and fails quietly once its sign-in ended; prefetch, which could
    /// run for minutes, stops now.
    func end() async {
        await prefetcher.cancel()
        await provider.endSession()
    }
}

/// One outbox per account for the launch, made on first use, so two replays of one queue never run at once. Failed
/// drains stay queued until the next flush.
actor Outboxes {
    private let make: @Sendable (AccountID) -> Outbox
    private var outboxes: [AccountID: Outbox] = [:]

    init(make: @escaping @Sendable (AccountID) -> Outbox) {
        self.make = make
    }

    func flush(_ id: AccountID) async {
        let outbox = outboxes[id] ?? make(id)
        outboxes[id] = outbox
        do {
            try await outbox.flush()
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "outbox")
                .error("Replay stopped: \(error, privacy: .public)")
        }
    }
}
