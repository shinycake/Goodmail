import MailCore
import MailStore
import MailUI
import OSLog
import UIKit

/// Smart mailboxes in a window (ADR-039): a box's list, and New Smart Mailbox from the menu bar.
extension SceneCoordinator {
    /// The box's conversations, listed as any mailbox's are and read as in All Mail, as search results are. Its mail
    /// is all on the device, so there is nothing older to fetch.
    func smartMailboxViewController(for id: SmartMailbox.ID) -> MailboxViewController {
        let model = model
        let known = sidebar?.smartDirectory.mailboxes.first { $0.id == id }
        // A box the sidebar hasn't shown yet, as when a window opens on it, is named once it is read.
        let database = model.database
        let naming: MailboxViewModel.Naming? =
            if known == nil { { await Self.title(of: id, in: database) } } else { nil }
        return MailboxViewController(
            viewModel: MailboxViewModel(
                mailbox: .allMail,
                title: known?.title ?? SmartMailbox.sectionTitle,
                naming: naming,
                accounts: model.accounts,
                source: .flat(
                    .whole { model.database.threads(inSmartMailbox: id, mailboxNames: Mailbox.standardNames) }),
                pins: { model.database.pinnedThreads() },
                refresh: { try await model.syncAll() },
                retryAlerts: { await model.refreshPush() },
                navigate: { [weak self] route in self?.handle(route) },
                readAhead: { model.readAhead($0) },
                actions: actions,
                conversationSources: ConversationSources(
                    messages: { try await model.messagesToAnswer(in: $0).map(\.id) },
                    source: { try await model.source(of: $0) }),
                interaction: window.interactionStyle,
                health: model.health),
            draftsDock: drafts.dock)
    }

    /// The box's title as stored now; `nil` once it's deleted or can't be read.
    private nonisolated static func title(of id: SmartMailbox.ID, in database: OffMainDatabase) async -> String? {
        do {
            return try await database.offMain { try $0.smartMailboxes().first { $0.id == id }?.title }
        } catch {
            Logger.windows.error("Couldn't read a smart mailbox's title: \(error, privacy: .private)")
            return nil
        }
    }

    /// New Smart Mailbox, wherever the window shows mail.
    func newSmartMailboxAnswer() -> CommandAnswer {
        guard uncoveredMail != nil else { return .unavailable }
        return .ready(perform: { [weak self] in self?.handle(.newSmartMailbox(SearchQuery(terms: []))) })
    }
}
