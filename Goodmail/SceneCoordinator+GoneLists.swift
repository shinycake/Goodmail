import MailCore
import MailStore
import MailUI
import UIKit

/// A window on a label or smart mailbox that is gone from the device gives way to the Inbox
/// (`WindowState.keeping(_:lists:)`): one restored after it was deleted, one deleted while the window shows it or is
/// back at the mailboxes over it, in this window or on another device, and one handed off that never syncs here
/// (`WindowState.ListCheck`). The window follows the lists here as the store changes, off the main actor, for as long
/// as it lives, so what it shows, saves and hands off never names a dead list, whatever its width.
extension SceneCoordinator {
    /// Follows the labels and smart mailboxes here, replacing what followed them before. `check` says when a list
    /// missing from them counts as gone. A failed observation leaves the window as it is.
    func followOwnLists(_ check: WindowState.ListCheck) {
        listsCheck?.cancel()
        listsCheck = Task { [weak self, lists = model.database.ownLists()] in
            var check = check
            do {
                for try await here in lists {
                    guard let self else { return }
                    // Only the viewer shows its list; a message window keeps reading where it was opened.
                    guard split != nil, let kept = check.next(shown, accounts: model.accounts.map(\.id), lists: here)
                    else { continue }
                    showKept(kept)
                }
            } catch {}
        }
    }

    /// Shows `kept`, which differs from what shows only in the list, or the mailbox the conversation reads in when that
    /// was the gone label: the list's screen alone is replaced, under the reader, or the whole viewer is rebuilt when
    /// the reader reads elsewhere now.
    /// TODO: slice 4's `MailScreens` reconciles every change this way; this goes once it does.
    private func showKept(_ kept: WindowState) {
        guard let split else { return }
        let sameReader = kept.reading == shown.reading
        move { $0 = kept }
        guard sameReader else { return showMailbox(kept) }
        let list = listViewController(for: kept.list)
        (list as? any ThreadSequence)?.mark(reading: kept.reading?.thread)
        if split.isCollapsed {
            guard let stack = navigation(for: .compact) else { return }
            (stack.viewControllers.first as? MailboxesViewController)?.selected = kept.destination
            // Back at the mailboxes the list isn't on the stack: it shows once the reader opens it.
            guard stack.viewControllers.count > 1 else { return }
            var screens = stack.viewControllers
            screens[1] = list
            stack.setViewControllers(screens, animated: false)
        } else {
            (navigation(for: .primary)?.viewControllers.first as? MailboxesViewController)?.selected = kept.destination
            navigation(for: .supplementary)?.setViewControllers([list], animated: false)
        }
    }
}
