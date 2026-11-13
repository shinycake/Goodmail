import UIKit

extension UIStackView {
    /// Lays the arranged views side by side, or one under the other at the accessibility text sizes, where side by
    /// side would truncate both. Follows the setting as it changes.
    func stacksVerticallyAtAccessibilitySizes() {
        func apply(_ stack: UIStackView) {
            let vertical = stack.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            stack.axis = vertical ? .vertical : .horizontal
            stack.alignment = vertical ? .leading : .firstBaseline
        }
        apply(self)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (stack: UIStackView, _) in apply(stack) }
    }
}
