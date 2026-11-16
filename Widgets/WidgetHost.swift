// MailIntents can't build on the Linux cloud build (docs/setup/cloud-builds.md); there the widget has no intents.
#if canImport(MailIntents)
    import AppIntents
    import MailCore
    import MailIntents
    import MailStore

    /// The intents the widget's buttons run, from the package shared with the app.
    struct WidgetAppIntents: AppIntentsPackage {
        static var includedPackages: [any AppIntentsPackage.Type] { [GoodmailIntentsPackage.self] }
    }

    /// The widget's side of the App Intents: its buttons archive through the same commands as the app, against the
    /// shared database (ADR-002). The widget can't reach the network, so the change waits in the outbox until the app
    /// next syncs; the conversation leaves the widget at once.
    struct WidgetHost: MailIntentsHost {
        let database: MailDatabase
        let commands: MailCommands

        init(database: MailDatabase) {
            self.database = database
            commands = MailCommands(store: database, replay: { _ in })
        }

        func accounts() throws -> [Account] { try database.accounts() }

        /// The widget offers no mailbox intents, so it names no mailboxes.
        func mailboxes(of account: AccountID) throws -> [NamedMailbox] { [] }

        func threads(_ ids: [ThreadSummary.ID]) throws -> [ThreadSummary] { try database.threads(ids) }

        func threads(in mailbox: Mailbox, limit: Int) throws -> [ThreadSummary] {
            try database.threads(in: mailbox, limit: limit)
        }

        func threads(matching text: String, limit: Int) throws -> [ThreadSummary] {
            try database.threads(matching: text, limit: limit)
        }

        // The widget's buttons only point at threads, so it reads no facts.
        func threadFacts(_ ids: [ThreadSummary.ID]) throws -> [MailFacts] { [] }
        func messageFacts(inThreads ids: [ThreadSummary.ID]) throws -> [MailFacts] { [] }
        func messageFacts(matching condition: MailCondition, in context: MailCondition.Context) throws -> [MailFacts] {
            []
        }
        func threadFacts(matching condition: MailCondition, in context: MailCondition.Context) throws -> [MailFacts] {
            []
        }

        func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) async throws -> MailCommands.Undo {
            try await commands.perform(action, on: threads)
        }

        func pin(_ threads: [ThreadSummary.ID], _ pinned: Bool) async throws -> MailCommands.Undo {
            try await commands.pin(threads, pinned)
        }

        func snooze(_ threads: [ThreadSummary.ID], until date: Date?) async throws -> MailCommands.Undo {
            if let date {
                try await commands.snooze(threads, until: date)
            } else {
                try await commands.unsnooze(threads)
            }
        }

        /// Unsubscribing, checking for mail and sending need the network and the app's sign-ins, which the widget
        /// doesn't hold. If one of these intents runs here, it fails with that reason instead of half-running.
        func unsubscribe(_ unsubscribe: Unsubscribe, account: AccountID) async throws -> ListUnsubscriber.Outcome {
            throw WidgetHostError.needsTheApp
        }

        func refresh() async throws { throw WidgetHostError.needsTheApp }

        func answer(_ answer: Answer, to message: Message.ID, inThread thread: ThreadSummary.ID) async throws -> Draft?
        {
            throw WidgetHostError.needsTheApp
        }

        func send(_ draft: Draft, at date: Date?) async throws { throw WidgetHostError.needsTheApp }

        func undo(_ undo: MailCommands.Undo) async throws {
            try await commands.undo(undo)
        }

        /// Opening intents run in the app, which the system launches for them.
        @MainActor func open(_ route: Route) {}
    }

    /// An intent that needs the network reached the widget, which can't fetch or send.
    enum WidgetHostError: Error {
        case needsTheApp
    }
#endif
