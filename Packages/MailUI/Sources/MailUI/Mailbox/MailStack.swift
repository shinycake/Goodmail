import UIKit

/// The narrow arrangement's stack: the mailboxes, a mail list pushed over them, and a thread over that.
///
/// The mail lists hide the system back button for the sidebar button (`sidebarBackItem`), and a hidden back button
/// turns off the edge swipe that goes back. So the stack decides that swipe itself: it goes back from any screen above
/// the root while no other push or pop is under way, and the screen's own gestures (a row's swipe actions, scrolling)
/// wait for it, as they do with the system back button. Touches away from the edge fail it at once, so they don't wait
/// long.
public final class MailStackController: UINavigationController, UIGestureRecognizerDelegate {
    public override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
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
