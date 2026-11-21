import MailCore
import MailStore
import MailUI
import UIKit

/// Smart mailboxes in a window (ADR-039): a box's list, and New Smart Mailbox from the menu bar.
extension SceneCoordinator {
    /// The box's conversations, listed as any mailbox's are and read as in All Mail, as search results are. Its mail
    /// is all on the device, so there is nothing older to fetch.
    func smartMailboxViewController(for id: SmartMailbox.ID) -> MailboxViewController {
        let model = model
        return MailboxViewController(
            viewModel: MailboxViewModel(
                mailbox: .allMail,
                title: smartMailbox(id)?.title ?? SmartMailbox.sectionTitle,
                accounts: model.accounts,
                source: .flat { model.database.threads(inSmartMailbox: id, mailboxNames: Mailbox.standardNames) },
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

    /// The box as stored now, which names its list and its window; `nil` once it's deleted.
    func smartMailbox(_ id: SmartMailbox.ID) -> SmartMailbox? {
        try? model.database.smartMailboxes().first { $0.id == id }
    }

    /// New Smart Mailbox, wherever the window shows mail.
    func newSmartMailboxAnswer() -> CommandAnswer {
        guard uncoveredMail != nil else { return .unavailable }
        return .ready(perform: { [weak self] in self?.handle(.newSmartMailbox(SearchQuery(terms: []))) })
    }
}
