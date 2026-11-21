import MailCore
import MailUI
import UIKit

/// What reaches the window from outside it (`Arrival`): it uncovers the window and shows what it opens in a list that
/// holds it (R3, R4), through the window's navigation like every other route.
extension SceneCoordinator {
    /// Takes `arrival` while the window is up.
    func arrive(_ arrival: Arrival) {
        switch arrival {
        case .route(let route): handle(route, from: .outside)
        case .link(let link): open(link)
        case .quickAction(let action): route(for: action).map { handle($0, from: .outside) }
        case .handoff(let state): showHandedOff(state)
        }
    }

    /// Applies what `arrival` changes of what the window shows to the state it restored, before its screens are first
    /// built (`WindowNavigation.Event.launched`), and returns what is left for once the window is visible: a screen
    /// to present, search, which begins in a list on screen, a link, or Handoff, which builds the screens itself.
    /// `nil` when nothing is left.
    func arriveBeforeShowing(_ arrival: Arrival) -> Arrival? {
        let route: Route? =
            switch arrival {
            case .route(let route): route
            case .quickAction(let action): self.route(for: action)
            case .link, .handoff: nil
            }
        guard let route, Self.movesBeforeShowing(route) else { return arrival }
        navigator.send(.launched(for: route))
        return nil
    }

    /// Whether `route` only moves what the window shows, so it applies before anything is built.
    private static func movesBeforeShowing(_ route: Route) -> Bool {
        switch route {
        case .thread, .mailbox, .scheduled, .snoozed, .smartMailbox:
            true
        case .search, .selection, .compose, .draft, .answer, .changeLabels, .move, .newSmartMailbox,
            .editSmartMailbox, .settings, .signInAgain, .newWindow:
            false
        }
    }

    /// What the window holds, as an arrival from outside sees it (`WindowChoice`).
    var holds: WindowFacts.Holds {
        switch screen {
        case .starting: .opening
        case .welcome, .offer: .noMail
        case .mailbox: .viewer(reading: shown.reading?.thread)
        case .message, .leaving: .message
        }
    }

    /// Clears what covers the window for an arrival from outside (R3), then calls `next`. Search and Select mode end
    /// in the list. Unless an alert, a sign-in, a transfer or the accounts offer is up (`Uncovering.blocks`), whose
    /// answer the arrival waits beneath, Settings and the sheets that only read or pick are dismissed, as their Close
    /// buttons do, and the message being written goes down to the drafts pill, kept.
    func uncover(then next: @escaping () -> Void) {
        (navigator.screens?.list as? MailboxViewController)?.endSearchAndSelection()
        let root = window.rootViewController ?? drafts
        let presented = Uncovering.presented(over: root)
        guard !Uncovering.blocks(presented) else { return next() }
        guard !presented.isEmpty else { return drafts.uncover(then: next) }
        root.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            drafts.uncover(then: next)
        }
    }
}

extension AppModel {
    /// The accounts whose Inbox isn't sorted into Gmail's categories: by the reader's choice, or because their
    /// service has none. All of such an Inbox is in Primary.
    var unsortedInboxAccounts: Set<AccountID> {
        Preferences.unsortedInboxAccounts.union(accounts.filter { !$0.service.hasInboxCategories }.map(\.id))
    }
}
