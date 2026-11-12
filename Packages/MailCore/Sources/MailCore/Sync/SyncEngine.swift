import Foundation

/// Keeps one account's local mail in step with its provider.
///
/// - **Resync** fills the offline window (ADR-007) page by page, each page saved with its progress.
/// - **Incremental sync** refetches the threads that changed since the cursor.
/// - **Backfill** fetches older threads when the user scrolls past the window.
///
/// Every step converges: replaying a step after a crash refetches and rewrites the same threads.
public actor SyncEngine {
    /// Inbox, Sent, Starred and Drafts keep 90 days; everything else 30 (ADR-007).
    public static let longWindowLabels = ["INBOX", "SENT", "STARRED", "DRAFT"]
    public static let longWindow: TimeInterval = 90 * 86_400
    public static let shortWindow: TimeInterval = 30 * 86_400

    public nonisolated let accountID: AccountID
    private let provider: any MailProvider
    private let store: any SyncStore
    private let now: @Sendable () -> Date
    private var running: Task<Void, any Error>?
    /// When this engine last asked for the address book, so a provider that refuses isn't asked on every sync.
    private var addressBookAttempt: Date?
    /// How long an address book is kept before it is fetched again.
    public static let addressBookAge: TimeInterval = 86_400

    public init(
        accountID: AccountID,
        provider: any MailProvider,
        store: any SyncStore,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.now = now
    }

    /// Brings the account up to date. Concurrent callers share the sync in progress.
    public func sync() async throws {
        if let running { return try await running.value }
        let task = Task { try await performSync() }
        running = task
        defer { running = nil }
        try await task.value
    }

    /// Fetches the page of `mailbox` threads just older than the oldest stored one, or its newest page when none
    /// are stored, as for Spam and Trash, which the resync leaves out. Returns whether older threads may remain.
    public func backfill(_ mailbox: Mailbox) async throws -> Bool {
        if let owner = mailbox.accountID, owner != accountID { return false }
        let oldest = try store.oldestThreadDate(in: mailbox, account: accountID)
        // One second of overlap, so threads sharing the oldest timestamp aren't skipped; rewriting them is harmless.
        let fetchedAt = now()
        let page = try await provider.threads(
            matching: ThreadQuery(label: mailbox.labelID, before: oldest?.addingTimeInterval(1)), pageToken: nil)
        try store.apply(StoreChanges(accountID: accountID, upserts: page.threads, fetchedAt: fetchedAt))
        let madeProgress = oldest.map { oldest in page.threads.contains { $0.date < oldest } } ?? !page.threads.isEmpty
        return madeProgress && page.nextPageToken != nil
    }

    /// Asks the provider for a page of threads matching `text`, the first or the one `pageToken` starts, and stores
    /// them. Returns their IDs, newest first, and the next page's token if there are more: the provider searches
    /// bodies and older mail the local index doesn't hold.
    public func search(_ text: String, pageToken: String? = nil) async throws -> SearchPage {
        let fetchedAt = now()
        let page = try await provider.threads(matching: ThreadQuery(text: text), pageToken: pageToken)
        try store.apply(StoreChanges(accountID: accountID, upserts: page.threads, fetchedAt: fetchedAt))
        return SearchPage(ids: page.threads.map(\.id), next: page.nextPageToken.map { [accountID: $0] } ?? [:])
    }

    /// The resync's queries, in order: Inbox first so the list fills quickly.
    static func stages(startedAt: Date) -> [ThreadQuery] {
        let long = startedAt.addingTimeInterval(-longWindow)
        return longWindowLabels.map { ThreadQuery(label: $0, since: long) }
            + [ThreadQuery(since: startedAt.addingTimeInterval(-shortWindow))]
    }

    private func performSync() async throws {
        // A signature that can't be read never holds up mail; the last one stays.
        async let signature = try? provider.signature()
        let labels = try await provider.labels()
        try store.apply(StoreChanges(accountID: accountID, labels: labels, signature: await signature))
        try await refreshAddressBookIfOld()
        switch try store.syncState(for: accountID) {
        case nil:
            try await fillWindow(from: try await startResync())
        case .resyncing(let resync):
            try await fillWindow(from: resync)
        case .current(let cursor):
            do {
                try await syncChanges(since: cursor)
            } catch ProviderError.cursorExpired {
                try await fillWindow(from: try await startResync())
            }
        }
    }

    /// Fetches the address book once a day. Failing to never holds up mail.
    private func refreshAddressBookIfOld() async throws {
        let started = now()
        let last = [try store.addressBookDate(for: accountID), addressBookAttempt].compactMap(\.self).max()
        if let last, started.timeIntervalSince(last) < Self.addressBookAge { return }
        addressBookAttempt = started
        guard let contacts = try? await provider.contacts() else { return }
        try store.apply(
            StoreChanges(accountID: accountID, addressBook: AddressBook(contacts: contacts, fetchedAt: started)))
    }

    private func startResync() async throws -> Resync {
        let startedAt = now()
        let resync = Resync(
            cursor: try await provider.currentCursor(),
            startedAt: startedAt,
            generation: Int(startedAt.timeIntervalSince1970)
        )
        try store.apply(StoreChanges(accountID: accountID, state: .resyncing(resync)))
        return resync
    }

    private func fillWindow(from start: Resync) async throws {
        var resync = start
        let stages = Self.stages(startedAt: resync.startedAt)
        while resync.stage < stages.count {
            let fetchedAt = now()
            let page = try await provider.threads(matching: stages[resync.stage], pageToken: resync.pageToken)
            if let next = page.nextPageToken {
                resync.pageToken = next
            } else {
                resync.stage += 1
                resync.pageToken = nil
            }
            try store.apply(
                StoreChanges(
                    accountID: accountID,
                    upserts: page.threads,
                    generation: resync.generation,
                    state: .resyncing(resync),
                    fetchedAt: fetchedAt
                )
            )
        }

        let sweep = Sweep(
            generation: resync.generation,
            allMailSince: resync.startedAt.addingTimeInterval(-Self.shortWindow),
            longWindowSince: resync.startedAt.addingTimeInterval(-Self.longWindow),
            longWindowLabels: Set(Self.longWindowLabels)
        )
        try store.apply(StoreChanges(accountID: accountID, sweep: sweep, state: .current(cursor: resync.cursor)))
        // Catch what changed while the window was filling.
        try await syncChanges(since: resync.cursor)
    }

    private func syncChanges(since cursor: String) async throws {
        let fetchedAt = now()
        let changes = try await provider.changes(since: cursor)
        let fetch =
            changes.threadIDs.isEmpty
            ? ThreadFetch(found: [], missing: [])
            : try await provider.threads(withIDs: changes.threadIDs.sorted())
        try store.apply(
            StoreChanges(
                accountID: accountID,
                upserts: fetch.found,
                deletions: fetch.missing,
                state: .current(cursor: changes.cursor),
                fetchedAt: fetchedAt
            )
        )
    }
}
