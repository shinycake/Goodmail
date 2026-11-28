// Apple ships the App Intents macros MailIntents uses only as a macOS compiler plugin, so the Linux cloud build
// can't build MailIntents and type-checks the app without it (docs/setup/cloud-builds.md).
#if canImport(MailIntents)
    import AppIntents
    import MailCore
    import MailIntents
    import MailStore
    import MailUI
    import OSLog
    import UIKit

    /// The intents the app offers, from the package shared with its extensions.
    struct GoodmailAppIntents: AppIntentsPackage {
        static var includedPackages: [any AppIntentsPackage.Type] { [GoodmailIntentsPackage.self] }
    }

    /// The app's side of the App Intents (ADR-012): reads come from the shared database, and routes go to the frontmost
    /// window's coordinator.
    nonisolated struct IntentsHost: MailIntentsHost {
        let database: OffMainDatabase
        let commands: MailCommands
        let routes: IntentRoutes
        let unsubscriber: ListUnsubscriber
        /// Fetches a thread's messages when the device has none of them cached.
        let providers: Providers
        /// Syncs every account, as pulling down the Inbox does.
        let syncAll: @Sendable () async throws -> Void
        /// Fetches a thread's messages into the store when the cached ones don't reach its newest.
        let loadThread: @Sendable (ThreadSummary.ID) async throws -> Void

        func accounts() async throws -> [Account] { try await database.offMain { try $0.accounts() } }

        func mailboxes(of account: AccountID) async throws -> [NamedMailbox] {
            let labels = try await database.offMain { try $0.labels(for: account) }
                .filter { $0.kind == .user && !$0.isHidden }
                .map {
                    MailboxDirectory.Label(
                        mailbox: Mailbox(labelID: $0.id, accountID: account), name: $0.name, color: nil)
                }
            let standard = Mailbox.standard(of: account)
            return (standard + labels.map(\.mailbox)).map { NamedMailbox(mailbox: $0, name: $0.title(labels: labels)) }
        }

        func threads(_ ids: [ThreadSummary.ID]) async throws -> [ThreadSummary] {
            try await database.offMain { try $0.threads(ids) }
        }

        func threads(in mailbox: Mailbox, limit: Int) async throws -> [ThreadSummary] {
            try await database.offMain { try $0.threads(in: mailbox, limit: limit) }
        }

        func threads(matching text: String, limit: Int) async throws -> [ThreadSummary] {
            try await database.offMain { try $0.threads(matching: text, limit: limit) }
        }

        func threadFacts(_ ids: [ThreadSummary.ID]) async throws -> [MailFacts] {
            try await database.offMain { try $0.threadFacts(ids, mailboxNames: Mailbox.standardNames) }
        }

        func messageFacts(inThreads ids: [ThreadSummary.ID]) async throws -> [MailFacts] {
            try await database.offMain { try $0.messageFacts(inThreads: ids, mailboxNames: Mailbox.standardNames) }
        }

        func messageFacts(matching condition: MailCondition, in context: MailCondition.Context) async throws
            -> [MailFacts]
        {
            try await database.offMain {
                try $0.messageFacts(matching: condition, in: context, mailboxNames: Mailbox.standardNames)
            }
        }

        func threadFacts(matching condition: MailCondition, in context: MailCondition.Context) async throws
            -> [MailFacts]
        {
            try await database.offMain {
                try $0.threadFacts(matching: condition, in: context, mailboxNames: Mailbox.standardNames)
            }
        }

        // Intents can run with the app in the background, as from Siri or a widget, so their writes keep it awake.
        func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) async throws -> MailCommands.Undo {
            try await BackgroundDatabaseWork.shared.run("Intent") { try await commands.perform(action, on: threads) }
        }

        func pin(_ threads: [ThreadSummary.ID], _ pinned: Bool) async throws -> MailCommands.Undo {
            try await BackgroundDatabaseWork.shared.run("Intent") { try await commands.pin(threads, pinned) }
        }

        func snooze(_ threads: [ThreadSummary.ID], until date: Date?) async throws -> MailCommands.Undo {
            try await BackgroundDatabaseWork.shared.run("Intent") {
                if let date {
                    try await commands.snooze(threads, until: date)
                } else {
                    try await commands.unsnooze(threads)
                }
            }
        }

        func unsubscribe(_ unsubscribe: Unsubscribe, account: AccountID) async throws -> ListUnsubscriber.Outcome {
            try await unsubscriber.unsubscribe(unsubscribe, account: account)
        }

        // `answer`, `data` and `source` run off the caller's actor, since IMAP and Outlook read the message index as
        // they fetch (ADR-043).
        @concurrent func answer(_ answer: Answer, to message: Message.ID, inThread thread: ThreadSummary.ID)
            async throws -> Draft?
        {
            let (accounts, cached) = try await database.offMain { database in
                (try database.accounts(), try database.cachedMessages(inThread: thread))
            }
            guard let account = accounts.first(where: { $0.id == thread.accountID }) else { return nil }
            var messages = cached
            if !messages.contains(where: { $0.id == message }) {
                messages = try await providers.provider(for: thread.accountID).messages(inThread: thread.threadID)
                    .sorted { $0.date < $1.date }
            }
            // Answering the message means answering it as the newest of its thread.
            guard let index = messages.firstIndex(where: { $0.id == message }) else { return nil }
            return answer.draft(
                answering: Array(messages[...index]), accountEmail: account.email, aliases: account.aliases,
                wording: .localized)
        }

        func loadMessages(of threads: [ThreadSummary.ID]) async throws {
            try await BackgroundDatabaseWork.shared.run("Intent") {
                for thread in threads { try await loadThread(thread) }
            }
        }

        @concurrent func data(for attachment: Attachment, in message: Message.ID) async throws -> Data {
            try await providers.provider(for: message.accountID).data(for: attachment, in: message)
        }

        @concurrent func source(of message: Message.ID) async throws -> Data {
            try await providers.provider(for: message.accountID).source(of: message)
        }

        func send(_ draft: Draft, at date: Date?) async throws {
            try await BackgroundDatabaseWork.shared.run("Intent") {
                if let date {
                    try await commands.schedule(draft, at: date)
                } else {
                    try await commands.send(draft, after: .zero)
                }
            }
        }

        func refresh() async throws {
            try await BackgroundDatabaseWork.shared.run("Intent") { try await syncAll() }
        }

        func undo(_ undo: MailCommands.Undo) async throws {
            try await BackgroundDatabaseWork.shared.run("Intent") { try await commands.undo(undo) }
        }

        func apply(_ focus: FocusFilter) async throws { try await database.offMain { try $0.apply(focus) } }

        @MainActor func open(_ route: Route) { routes.open(route) }

        @MainActor func openThread() -> ThreadSummary.ID? { routes.openThread }
    }

    extension SpotlightIndexer {
        /// Keeps Spotlight in step with each bulk change to the stored mail. A failure leaves the index as it was until
        /// the next change; it is logged, since nothing on screen depends on it.
        nonisolated func follow(_ change: AppModel.MailChange) async {
            do {
                switch change {
                case .synced: try await refresh()
                case .accountRemoved: try await rebuild()
                }
            } catch {
                Logger(subsystem: "com.idanbirman.goodmail", category: "spotlight")
                    .error("Couldn't update Spotlight: \(error, privacy: .private)")
            }
        }
    }
#endif
