import MailCore
import MailStore
import MailUI
import UIKit

/// The window's side of its navigation (`WindowNavigator`): what it hears of the reader's changes to mail and of the
/// lists and devices around it, and what it does for the navigation that the screens don't.
extension SceneCoordinator {
    /// Follows the navigation and the reader's changes. Called once, as the window is made.
    func followNavigation() {
        navigator.stateChanged = { [weak self] _ in self?.publishActivity() }
        navigator.present = { [weak self] presentation in self?.present(presentation) }
        navigator.leaveWindow = { [weak self] in self?.leaveMessage() }
        navigator.uncover = { [weak self] next in self?.uncover(then: next) }
        navigator.say = { [actions] notice in actions.say(notice.text) }
        // A screen presented over a window not yet on screen, as at a cold launch, would be dropped (D14): the
        // navigation holds what it presents until the window is visible in an active scene.
        navigator.isOnScreen = { [weak window] in
            guard let window else { return false }
            return !window.isHidden && window.windowScene?.activationState == .foregroundActive
        }
        deviceObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIScene.didActivateNotification, object: window.windowScene, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.navigator.cameOnScreen() }
            })
        // The window's actions tell it of each change as it is asked, before it applies, and of each Undo; what sync,
        // other devices, alerts and other windows change only changes rows (R6).
        actions.changed = { [weak self] change in self?.readerAsked(change) }
        actions.undone = { [weak self] change in self?.readerUndid(change) }
    }

    private func readerAsked(_ change: MailChange) {
        navigator.send(
            .changed(
                change, reader: readerOnShow?.navigationReader, front: navigator.screens?.front?.navigationFront))
    }

    private func readerUndid(_ change: MailChange) {
        navigator.send(.undone(change, rows: navigator.screens?.front?.frontRows ?? []))
    }

    /// The reader on show: the viewer's, or alone in a message window.
    private var readerOnShow: ThreadViewController? {
        switch screen {
        case .message(let content, _):
            (content as? UINavigationController)?.viewControllers.first as? ThreadViewController
        case .mailbox:
            navigator.screens?.reader
        case .starting, .welcome, .offer, .leaving:
            nil
        }
    }

    /// Search began or ended in the list, so the rows the reader would go on in changed (R9).
    func searchToggled(_ on: Bool) {
        navigator.send(.searching(on))
    }

    /// Follows the labels and smart mailboxes here for as long as the window lives, off the main actor, so a list gone
    /// from the device gives way to the Inbox (`WindowState.keeping(_:lists:)`): one restored after it was deleted, one
    /// deleted while the window shows it, here or on another device, and one handed off that never syncs here
    /// (`WindowState.ListCheck`). It replaces what followed them before, and starts with the lists as they are now. A
    /// failed observation leaves the window as it is.
    func followOwnLists() {
        listsCheck?.cancel()
        listsCheck = Task { [weak self, lists = model.database.ownLists()] in
            do {
                for try await here in lists {
                    guard let self else { return }
                    navigator.send(.lists(here, accounts: model.accounts.map(\.id)))
                }
            } catch {}
        }
    }

    /// Shows what another device handed off, in this window, laid out as this window is
    /// (`WindowNavigation.Event.handedOff`). Its list may not be synced here yet.
    func showHandedOff(_ state: WindowState) {
        guard !model.accounts.isEmpty else { return }
        navigator.leaveScreens()
        navigator.send(.handedOff(state, accounts: model.accounts.map(\.id)))
        showMailbox()
        followOwnLists()
    }
}

extension SceneCoordinator: UISplitViewControllerDelegate {
    // The arrangement the window changes to catches up with what shows, keeping its screens where they still fit.
    func splitViewControllerDidCollapse(_ splitViewController: UISplitViewController) {
        navigator.arrangementChanged()
    }

    func splitViewControllerDidExpand(_ splitViewController: UISplitViewController) {
        navigator.arrangementChanged()
    }
}
