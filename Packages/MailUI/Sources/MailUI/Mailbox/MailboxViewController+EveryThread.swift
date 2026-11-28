import MailCore
import UIKit

/// Select All and Empty Trash act on every thread in the mailbox, not only on those its window lists (ADR-045), so they
/// wait for the store to list them all.
extension MailboxViewController {
    /// Runs `wait`, which waits for every thread, as the list's one such wait: a newer one replaces it, and the list
    /// going away cancels it. The newer one starts once the one it replaces has let the whole mailbox go, so that
    /// letting go can't take it from under the newer one, as when Empty Trash is tapped twice.
    func whenEveryThread(_ wait: @escaping (MailboxViewModel) async -> Void) {
        let replaced = everyThreadWait
        replaced?.cancel()
        everyThreadWait = Task { [viewModel] in
            await replaced?.value
            guard !Task.isCancelled else { return }
            await wait(viewModel)
        }
    }
}
