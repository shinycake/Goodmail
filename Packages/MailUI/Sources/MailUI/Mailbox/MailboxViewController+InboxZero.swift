import MailCore
import SwiftUI
public import UIKit

extension MailboxViewController {
    /// Puts the Inbox Zero scene behind the list, where pull to refresh and the list's own touches keep working
    /// over it.
    func installInboxZero(_ model: InboxZeroModel) {
        model.go = { [weak self] in self?.show($0) }
        model.play = { [weak self] in self?.playPlaneGame(from: $0) }
        model.laidOut = { [weak self] in self?.placeInboxZero() }
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
            inboxZero.leave()
            return
        }
        if case .inboxZero = previous, inboxZero.showing != nil {
            inboxZero.point(to: pointing)
            return
        }
        let arrival = InboxZeroArrival(
            onScreen: view.window != nil, hadThreads: previous == nil,
            sinceRemoval: lastRemoval.map { ContinuousClock.now - $0 })
        inboxZero.arrive(InboxZeroShowing(arrival: arrival, arrivedAt: .now, pointing: pointing))
        // The row VoiceOver was on is gone, so it moves to the words that say why.
        if arrival == .earned {
            SystemAccessibility.post(.layoutChanged, argument: collectionView.backgroundView)
        }
    }

    /// Lends the window's sky this list's scene while the scene can be seen, so its planes fly across the window and
    /// the pane beside it carries its doodles on, and takes it back once it can't: the list went off screen, or search
    /// results cover it, which they do without the list disappearing. The list calls this as it appears and
    /// disappears and as search comes and goes.
    func lendInboxZero() {
        guard let inboxZero else { return }
        inboxZeroLoan.update(
            inboxZero, found: (splitViewController as? MailSplitViewController)?.inboxZeroSky,
            shows: viewIfLoaded?.window != nil && search?.isActive != true)
    }

    /// `stage` in the window's coordinates, which are the sky's and the game's. Converted from the view hosting the
    /// scene, which is right even while the list is pulled and the scene moves with it.
    func inWindow(_ stage: InboxZeroStage) -> InboxZeroStage? {
        guard let backdrop = collectionView.backgroundView as? InboxZeroBackdrop else { return nil }
        return stage.converted { backdrop.scene.convert($0, to: nil) }
    }

    /// Keeps the scene between the list's bars and beside a sidebar floating over the list, and moves it down with the
    /// list as it is pulled to refresh, and tells the sky where it is in the window.
    func placeInboxZero() {
        guard let inboxZero, let backdrop = collectionView.backgroundView as? InboxZeroBackdrop else { return }
        // Refreshing adds the spinner's room to the top inset. The scene keeps its place between the bars at rest, and
        // the pull is measured from there, so it stays under the title while the spinner shows.
        if collectionView.refreshControl?.isRefreshing != true {
            // The sides come from the list's container: in a right-to-left layout the list reports a sidebar on its right
            // as being on its left.
            let clear = EdgeInsets(
                bars: collectionView.adjustedContentInset, sides: view.safeAreaInsets,
                rightToLeft: view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
            if inboxZero.insets != clear { inboxZero.insets = clear }
        }
        backdrop.pull(by: max(-(collectionView.contentOffset.y + inboxZero.insets.top), 0))
        let onScreen = view.window == nil ? nil : inboxZero.stage.flatMap(inWindow)
        if inboxZero.onScreen != onScreen { inboxZero.onScreen = onScreen }
    }
}

extension MailboxViewController: UISearchControllerDelegate {
    /// Search results cover the Inbox Zero scene, so its planes stop flying over them.
    /// Also tells the window the rows on show changed (`searchToggled`).
    public func willPresentSearchController(_ searchController: UISearchController) {
        lendInboxZero()
        searchToggled?()
    }

    public func didDismissSearchController(_ searchController: UISearchController) {
        lendInboxZero()
        searchToggled?()
    }
}

extension EdgeInsets {
    /// What the Inbox Zero scene keeps clear of: the list's `bars` above and below, and at the `sides` whatever the
    /// safe area leaves out, which is a sidebar floating over the list on an iPad or the camera housing in landscape.
    nonisolated init(bars: UIEdgeInsets, sides: UIEdgeInsets, rightToLeft: Bool) {
        self.init(
            top: bars.top, leading: rightToLeft ? sides.right : sides.left, bottom: bars.bottom,
            trailing: rightToLeft ? sides.left : sides.right)
    }
}

/// The list's background, holding the Inbox Zero scene. The list sets its background's frame on every layout, which
/// undoes a transform on the background itself, so the pull moves the scene inside it.
///
/// Where the scene sits follows from the list's bounds alone, and UIKit already animates those when it settles a pull
/// into the refreshing position. So neither the backdrop's place nor the pull animates on its own: the list's
/// `scrollViewDidScroll` for that settle runs inside UIKit's animation, and an animated pull there would move the scene
/// the same distance a second time, dropping it below its place until the animation catches up.
final class InboxZeroBackdrop: UIView {
    /// The view hosting the scene, whose space is the scene's stage space.
    let scene: UIView

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

    override func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
        event == "position" ? NSNull() : super.action(for: layer, forKey: event)
    }

    func pull(by distance: CGFloat) {
        UIView.performWithoutAnimation { scene.transform = CGAffineTransform(translationX: 0, y: distance) }
    }
}
