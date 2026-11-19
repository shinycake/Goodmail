import MailCore
import MailStore
import MailUI
import UIKit

/// The Home Screen quick actions: what touching and holding the app icon offers. Apple suggests setting them as the
/// app leaves the foreground, so the menu matches the accounts and drafts as the reader left them.
final class QuickActionMenu {
    private let model: AppModel
    /// The newest refresh, which a newer one replaces.
    private var refreshing: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    isolated deinit {
        refreshing?.cancel()
    }

    /// Offers the actions for the accounts and the newest draft here now. A draft that can't be read, as when the
    /// database is already suspended, leaves the menu as it was rather than dropping the draft from it.
    func refresh() {
        refreshing?.cancel()
        let accounts = model.accounts
        refreshing = Task { [database = model.database] in
            guard let draft = await Self.newestDraft(in: database), !Task.isCancelled else { return }
            UIApplication.shared.shortcutItems = UIApplicationShortcutItem.quickActions(
                accounts: accounts, newestDraft: draft.thread)
        }
    }

    /// The newest thread in Drafts, or `nil` when it can't be read.
    @concurrent private static func newestDraft(in database: MailDatabase) async -> NewestDraft? {
        guard let threads = try? database.threads(in: .drafts, limit: 1) else { return nil }
        return NewestDraft(thread: threads.first)
    }

    /// What reading Drafts found: its newest thread, or none.
    private struct NewestDraft {
        let thread: ThreadSummary?
    }
}
