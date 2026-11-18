public import UIKit

/// The narrow arrangement's stack: the mailboxes, a mail list pushed over them, and a thread over that.
///
/// The mail lists hide the system back button for the sidebar button (`sidebarBackItem`), and a hidden back button
/// turns off the edge swipe that goes back. So the stack decides that swipe itself: it goes back from any screen above
/// the root while no other push or pop is under way, and the screen's own gestures (a row's swipe actions, scrolling)
/// wait for it, as they do with the system back button. Touches away from the edge fail it at once, so they don't wait
/// long.
///
/// A push or pop changes the bottom toolbar, so the split view places what sits on its line (the undo toast, the
/// minimized messages) again along with it, and once more as it ends or is called off.
public final class MailStackController: UINavigationController, UIGestureRecognizerDelegate {
    public override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)
        relayOutSplitAlong()
    }

    public override func popViewController(animated: Bool) -> UIViewController? {
        defer { relayOutSplitAlong() }
        return super.popViewController(animated: animated)
    }

    public override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        defer { relayOutSplitAlong() }
        return super.popToRootViewController(animated: animated)
    }

    public override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        super.setViewControllers(viewControllers, animated: animated)
        relayOutSplitAlong()
    }

    /// Lays the split view out again with the transition under way, and once it ends; at once without one.
    private func relayOutSplitAlong() {
        guard let split = splitViewController?.view else { return }
        split.setNeedsLayout()
        guard let transition = transitionCoordinator else { return }
        transition.animate(
            alongsideTransition: { _ in split.layoutIfNeeded() }, completion: { _ in split.setNeedsLayout() })
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && transitionCoordinator == nil
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        guard let screen = topViewController?.view, let view = other.view else { return false }
        return view.isDescendant(of: screen)
    }
}
