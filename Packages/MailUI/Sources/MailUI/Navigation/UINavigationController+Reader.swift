import MailCore
public import UIKit

extension UINavigationController {
    /// Shows `reader` on this narrow stack: pushed over the list when no reader is on show, or in the place of the one
    /// that is, with a short cross-fade (none under Reduce Motion), so the stack never holds two and Back goes to the
    /// list (R1).
    public func place(_ reader: ThreadViewController) {
        switch ReaderStack(readers: viewControllers.map { $0 is ThreadViewController }) {
        case .push:
            pushViewController(reader, animated: view.window != nil)
        case .replace(let keeping):
            let stack = Array(viewControllers.prefix(keeping)) + [reader]
            guard view.window != nil, !SystemAccessibility.reducesMotion else {
                return setViewControllers(stack, animated: false)
            }
            UIView.transition(with: view, duration: 0.25, options: .transitionCrossDissolve) {
                self.setViewControllers(stack, animated: false)
            }
        }
    }
}
