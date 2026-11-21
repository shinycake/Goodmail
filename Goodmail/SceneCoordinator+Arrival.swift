import MailCore
import MailUI
import UIKit

/// What reaches the window from outside it (`Arrival`): it uncovers the window and shows what it opens in a list that
/// holds it (R3, R4), through the window's navigation like every other route.
extension SceneCoordinator {
    /// Takes `arrival` while the window is up.
    func arrive(_ arrival: Arrival) {
        if case .handoff(let state) = arrival { return showHandedOff(state) }
        route(for: arrival).map { handle($0, from: .outside) }
    }

    /// Applies `arrival` to the state the window restored, before its screens are first built
    /// (`WindowNavigation.Event.launched`): what it presents or begins waits in the navigation for the window to be on
    /// screen. Returns Handoff, which builds the screens itself once they are, and `nil` otherwise.
    func arriveBeforeShowing(_ arrival: Arrival) -> Arrival? {
        if case .handoff = arrival { return arrival }
        route(for: arrival).map { navigator.send(.launched(for: $0)) }
        return nil
    }

    /// Where `arrival`, other than Handoff, goes: a link opens a transfer code or a `mailto:` message, and a quick
    /// action its route. `nil` for one that goes nowhere, as a `mailto:` link with no account to send from.
    private func route(for arrival: Arrival) -> Route? {
        switch arrival {
        case .route(let route): route
        case .quickAction(let action): route(for: action)
        case .link(let link): route(forLink: link)
        case .handoff: nil
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
    /// in the list. Only screens known to be safe to close are dismissed, as their Close buttons do
    /// (`ArrivalCover`), and the message being written goes down to the drafts pill, kept. Anything else, as an
    /// alert, a sign-in, a transfer or the accounts offer, stays: the arrival waits beneath its answer.
    func uncover(then next: @escaping () -> Void) {
        (navigator.screens?.list as? MailboxViewController)?.endSearchAndSelection()
        let root = window.rootViewController ?? drafts
        let presented = ArrivalCover.presented(over: root)
        guard !WebAuthentication.isSigningIn(in: window), ArrivalCover.dismissible(presented) else { return next() }
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
