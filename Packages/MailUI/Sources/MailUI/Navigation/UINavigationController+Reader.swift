public import UIKit

extension UINavigationController {
    /// Shows `reader` in place of the conversation on top of this narrow stack, or over the list when none is: with a
    /// short cross-fade, as the next conversation takes the place of one put away, or none under Reduce Motion. Back
    /// still goes to the list.
    public func showReader(_ reader: ThreadViewController) {
        let stack = viewControllers.filter { !($0 is ThreadViewController) } + [reader]
        guard view.window != nil, !SystemAccessibility.reducesMotion else {
            return setViewControllers(stack, animated: false)
        }
        UIView.transition(with: view, duration: 0.25, options: .transitionCrossDissolve) {
            self.setViewControllers(stack, animated: false)
        }
    }
}
