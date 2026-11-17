import MailCore
import SwiftUI
import UIKit

extension MailboxViewController {
    /// Puts the Inbox Zero scene behind the list, where pull to refresh and the list's own touches keep working
    /// over it.
    func installInboxZero(_ model: InboxZeroModel) {
        model.go = { [weak self] in self?.show($0) }
        collectionView.backgroundView = InboxZeroBackdrop(
            scene: UIHostingConfiguration { InboxZeroView(model: model) }.margins(.all, 0).makeContentView())
    }

    /// The scene to show in an empty Inbox, or `nil` where the Inbox keeps today's "No Mail": a category other than
    /// Primary, and an account with a sync problem, whose empty Inbox can't be vouched for.
    func inboxZeroState() -> EmptyState? {
        guard inboxZero != nil, viewModel.category == nil || viewModel.category == .primary,
            viewModel.problems.isEmpty
        else { return nil }
        let pointing = viewModel.categoryWithUnread.map {
            InboxZeroPointer(category: $0, unread: viewModel.categoryUnreadCounts[$0, default: 0])
        }
        return .inboxZero(pointing: pointing)
    }

    /// Shows the scene for `state`, or takes it away. `previous` is the state the list is leaving, which tells an
    /// Inbox the reader just cleared from one found empty.
    func showInboxZero(for state: EmptyState?, after previous: EmptyState?) {
        guard let inboxZero else { return }
        guard case .inboxZero(let pointing) = state else {
            inboxZero.showing = nil
            return
        }
        if case .inboxZero = previous, var showing = inboxZero.showing {
            showing.pointing = pointing
            inboxZero.showing = showing
            return
        }
        let arrival = InboxZeroArrival(
            onScreen: view.window != nil, hadThreads: previous == nil,
            sinceRemoval: lastRemoval.map { ContinuousClock.now - $0 })
        inboxZero.showing = InboxZeroShowing(arrival: arrival, arrivedAt: .now, pointing: pointing)
        // The row VoiceOver was on is gone, so it moves to the words that say why.
        if arrival == .earned {
            SystemAccessibility.post(.layoutChanged, argument: collectionView.backgroundView)
        }
    }

    /// Keeps the scene between the list's bars, and moves it down with the list as it is pulled to refresh.
    func placeInboxZero() {
        guard let inboxZero, let backdrop = collectionView.backgroundView as? InboxZeroBackdrop else { return }
        // Refreshing adds the spinner's room to the top inset. The scene keeps its place between the bars at rest, and
        // the pull is measured from there, so it stays under the title while the spinner shows.
        if collectionView.refreshControl?.isRefreshing != true {
            let insets = collectionView.adjustedContentInset
            let bars = EdgeInsets(top: insets.top, leading: 0, bottom: insets.bottom, trailing: 0)
            if inboxZero.insets != bars { inboxZero.insets = bars }
        }
        backdrop.pull(by: max(-(collectionView.contentOffset.y + inboxZero.insets.top), 0))
    }
}

/// The list's background, holding the Inbox Zero scene. The list sets its background's frame on every layout, which
/// undoes a transform on the background itself, so the pull moves the scene inside it.
private final class InboxZeroBackdrop: UIView {
    private let scene: UIView

    init(scene: UIView) {
        self.scene = scene
        super.init(frame: .zero)
        addSubview(scene)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Bounds and center rather than frame, which a transform makes meaningless.
        scene.bounds = bounds
        scene.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func pull(by distance: CGFloat) {
        scene.transform = CGAffineTransform(translationX: 0, y: distance)
    }
}
