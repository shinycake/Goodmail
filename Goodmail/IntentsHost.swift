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
        let database: MailDatabase
        let commands: MailCommands
        let routes: IntentRoutes
        let unsubscriber: ListUnsubscriber
        /// Fetches a thread's messages when the device has none of them cached.
        let providers: Providers
        /// Syncs every account, as pulling down the Inbox does.
        let syncAll: @Sendable () async throws -> Void

        func accounts() throws -> [Account] { try database.accounts() }

        func mailboxes(of account: AccountID) throws -> [NamedMailbox] {
            let labels = try database.labels(for: account)
                .filter { $0.kind == .user && !$0.isHidden }
                .map {
                    MailboxDirectory.Label(
                        mailbox: Mailbox(labelID: $0.id, accountID: account), name: $0.name, color: nil)
                }
            let standard = Mailbox.standard.map { Mailbox(labelID: $0.labelID, accountID: account) }
            return (standard + labels.map(\.mailbox)).map { NamedMailbox(mailbox: $0, name: $0.title(labels: labels)) }
        }

        func threads(_ ids: [ThreadSummary.ID]) throws -> [ThreadSummary] { try database.threads(ids) }

        func threads(in mailbox: Mailbox, limit: Int) throws -> [ThreadSummary] {
            try database.threads(in: mailbox, limit: limit)
        }

        func threads(matching text: String, limit: Int) throws -> [ThreadSummary] {
            try database.threads(matching: text, limit: limit)
        }

        func threadFacts(_ ids: [ThreadSummary.ID]) throws -> [MailFacts] {
            try database.threadFacts(ids, mailboxNames: Self.mailboxNames)
        }

        func messageFacts(inThreads ids: [ThreadSummary.ID]) throws -> [MailFacts] {
            try database.messageFacts(inThreads: ids, mailboxNames: Self.mailboxNames)
        }

        func messageFacts(matching condition: MailCondition, in context: MailCondition.Context) throws -> [MailFacts] {
            try database.messageFacts(matching: condition, in: context, mailboxNames: Self.mailboxNames)
        }

        func threadFacts(matching condition: MailCondition, in context: MailCondition.Context) throws -> [MailFacts] {
            try database.threadFacts(matching: condition, in: context, mailboxNames: Self.mailboxNames)
        }

        /// The standard mailboxes' names, as the mailbox list shows them, by label ID.
        private static var mailboxNames: [String: String] {
            Dictionary(
                Mailbox.standard.compactMap { mailbox in mailbox.labelID.map { ($0, mailbox.title(labels: [])) } },
                uniquingKeysWith: { first, _ in first })
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

        func answer(_ answer: Answer, to message: Message.ID, inThread thread: ThreadSummary.ID) async throws -> Draft?
        {
            guard let account = try database.accounts().first(where: { $0.id == thread.accountID }) else { return nil }
            var messages = try database.cachedMessages(inThread: thread)
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

        @MainActor func open(_ route: Route) { routes.open(route) }
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
                    .error("Couldn't update Spotlight: \(error, privacy: .public)")
            }
        }
    }
#endif
