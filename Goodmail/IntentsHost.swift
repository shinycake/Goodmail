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

        func cachedMessages(inThread id: ThreadSummary.ID) throws -> [Message] {
            try database.cachedMessages(inThread: id)
        }

        func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) async throws -> MailCommands.Undo {
            try await commands.perform(action, on: threads)
        }

        func undo(_ undo: MailCommands.Undo) async throws {
            try await commands.undo(undo)
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
