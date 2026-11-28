public import Foundation

/// Keeps one account's local mail in step with its provider.
///
/// - **Resync** fills the offline window (ADR-007) page by page, each page saved with its progress.
/// - **Incremental sync** refetches the threads that changed since the cursor.
/// - **Backfill** fetches older threads when the user scrolls past the window.
///
/// Every step converges: replaying a step after a crash refetches and rewrites the same threads.
public actor SyncEngine {
    public nonisolated let accountID: AccountID
    let provider: any MailProvider
    let store: any SyncStore
    let now: @Sendable () -> Date
    /// How much of the account it keeps.
    public nonisolated let scope: SyncScope
    private var running: Task<Void, any Error>?
    /// When this engine last asked for the address book, so a provider that refuses isn't asked on every sync.
    private var addressBookAttempt: Date?
    /// How long an address book is kept before it is fetched again.
    public static let addressBookAge: TimeInterval = 86_400
    /// A sync's read of the signature is dropped when an edit overtook it.
    private var signatureReads = OvertakingWrites()
    /// An older read of the labels never replaces the labels a newer one stored.
    private var labelReads = LatestRead()

    public init(
        accountID: AccountID,
        provider: any MailProvider,
        store: any SyncStore,
        scope: SyncScope = .window(.handheld),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.scope = scope
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

    /// Fetches only what changed since the cursor, for the notification extension's short, memory-tight run: no
    /// labels, address book or resync. Returns the threads that changed; none when the account isn't current, since
    /// filling the window is left to the app.
    public func catchUp() async throws -> [ThreadSummary] {
        guard case .current(let cursor) = try store.syncState(for: accountID) else { return [] }
        do {
            return try await syncChanges(since: cursor)
        } catch ProviderError.cursorExpired {
            return []
        }
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

    /// What a resync lists, in order, from the one set of long-window labels its sweep then covers: Inbox first so
    /// the list fills quickly, and the Inbox alone for its head.
    static func plan(startedAt: Date, scope: SyncScope = .window(.handheld)) -> Resync.Plan {
        let window = scope.offlineWindow
        let labels = OfflineWindow.longWindowLabels
        let long = startedAt.addingTimeInterval(-window.longWindow)
        let queries =
            switch scope {
            case .window:
                labels.map { ThreadQuery(label: $0, since: long) }
                    + [ThreadQuery(since: startedAt.addingTimeInterval(-window.shortWindow))]
            case .inboxHead:
                [ThreadQuery(label: SystemLabel.inbox, since: long)]
            }
        return Resync.Plan(queries: queries, sweeping: Set(labels))
    }

    /// Makes `text` the account's signature: at the service first when it keeps one, so a refused edit changes
    /// nothing, then on the device. Empty removes it. Returns the revision of the stored accounts the write left
    /// (`SyncStore.storeSignature(_:for:)`).
    @discardableResult public func setSignature(_ text: String) async throws -> Int {
        if let service = provider as? any SendAsSyncing { try await service.setSignature(text) }
        signatureReads.wrote()
        return try store.storeSignature(text, for: accountID)
    }

    /// Makes a user label named `name`, a path such as `Projects/Goodmail`, at the service, then stores the
    /// account's labels with it. Returns the new label.
    public func createLabel(named name: String) async throws -> MailLabel {
        let label = try await provider.createLabel(named: name)
        try await refreshLabels()
        return label
    }

    /// Gives the user label `id` the path `name` at the service, then stores the account's labels.
    public func renameLabel(_ id: String, to name: String) async throws {
        try await provider.renameLabel(id, to: name)
        try await refreshLabels()
    }

    /// Deletes the user label `id` at the service, then stores the account's labels and refetches the threads that
    /// carried it or a label nested in it: the service may move or remove their mail without reporting it changed.
    public func deleteLabel(_ id: String) async throws {
        let labels = try store.labels(for: accountID)
        let nested = labels.first { $0.id == id }.map { labels.nested(under: $0.name) } ?? []
        try await deleteLabels([id], carrying: Set(nested.map(\.id) + [id]))
    }

    /// Reads and stores the account's labels, unless a newer read started meanwhile.
    func refreshLabels() async throws {
        let ticket = labelReads.begin()
        let labels = try await provider.labels()
        guard labelReads.isLatest(ticket) else { return }
        try store.apply(StoreChanges(accountID: accountID, labels: labels))
    }

    private func performSync() async throws {
        // A signature and aliases that can't be read never hold up mail; the last ones stay. A signature read before
        // an edit made meanwhile is older than the edit, so it's dropped, as are labels read before a label edit's
        // own read.
        let signatureRead = signatureReads.read()
        let labelRead = labelReads.begin()
        async let read = Self.sendAs(from: provider)
        let labels = try await provider.labels()
        let sendAs = await read
        try store.apply(
            StoreChanges(
                accountID: accountID, labels: labelReads.isLatest(labelRead) ? labels : nil,
                signature: signatureReads.isCurrent(signatureRead) ? sendAs?.signature : nil, aliases: sendAs?.aliases))
        if case .window = scope { try await refreshAddressBookIfOld() }
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

    /// The service's signature and aliases; `nil` when it keeps none or can't be read.
    private static func sendAs(from provider: any MailProvider) async -> SendAs? {
        guard let service = provider as? any SendAsSyncing else { return nil }
        return try? await service.sendAs()
    }

    /// Fetches the address book once a day. Failing to never holds up mail.
    private func refreshAddressBookIfOld() async throws {
        let started = now()
        let last = [try store.addressBookDate(for: accountID), addressBookAttempt].compactMap(\.self).max()
        if let last, started.timeIntervalSince(last) < Self.addressBookAge { return }
        addressBookAttempt = started
        guard let book = try? await Self.addressBook(from: provider, fetchedAt: started) else { return }
        try store.apply(StoreChanges(accountID: accountID, addressBook: book))
    }

    private static func addressBook(from provider: any MailProvider, fetchedAt: Date) async throws -> AddressBook {
        guard let service = provider as? any ContactPhotoSyncing else {
            return AddressBook(contacts: try await provider.contacts(), fetchedAt: fetchedAt)
        }
        let listed = try await service.contactsWithPhotos()
        return AddressBook(contacts: listed.contacts, photos: listed.photos, fetchedAt: fetchedAt)
    }

    private func startResync() async throws -> Resync {
        let startedAt = now()
        let resync = Resync(
            cursor: try await provider.currentCursor(),
            startedAt: startedAt,
            generation: Int(startedAt.timeIntervalSince1970)
        )
        try store.apply(StoreChanges(accountID: accountID, progress: .resyncing(resync)))
        return resync
    }

    private func fillWindow(from start: Resync) async throws {
        var resync = start
        let sweeping: Set<String>
        listing: while true {
            switch resync.position {
            case .unplanned:
                // Planned here, not when it began, so a resync saved before its first page lists what this build
                // lists.
                resync.plan(Self.plan(startedAt: resync.startedAt, scope: scope))
            case .listing(let query, let pageToken, _, _):
                let fetchedAt = now()
                let page = try await provider.threads(matching: query, pageToken: pageToken)
                resync.record(page, limit: scope.resyncLimit)
                try store.apply(
                    StoreChanges(
                        accountID: accountID, upserts: page.threads, progress: .resyncing(resync),
                        fetchedAt: fetchedAt))
            case .listed(let labels):
                sweeping = labels
                break listing
            }
        }

        // The labels the plan listed for the long window, not this build's, which may list others.
        let sweep = Sweep(
            generation: resync.generation,
            allMailSince: resync.startedAt.addingTimeInterval(-scope.offlineWindow.shortWindow),
            longWindowSince: resync.startedAt.addingTimeInterval(-scope.offlineWindow.longWindow),
            longWindowLabels: sweeping
        )
        try store.apply(StoreChanges(accountID: accountID, progress: .resynced(sweep, cursor: resync.cursor)))
        // Catch what changed while the window was filling.
        try await syncChanges(since: resync.cursor)
    }

    /// Returns the threads it stored.
    @discardableResult
    private func syncChanges(since cursor: String) async throws -> [ThreadSummary] {
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
                progress: .current(cursor: changes.cursor),
                fetchedAt: fetchedAt
            )
        )
        return fetch.found
    }
}
