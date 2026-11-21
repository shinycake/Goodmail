public import MailCore
public import UIKit

extension WindowNavigation.Arrangement {
    /// How a window with `traits` lays out its viewer: one stack when it is narrow, columns otherwise, as the split view
    /// collapses. It holds before the split view is in a window, which only knows once it lays out.
    public init(_ traits: UITraitCollection) {
        self = traits.horizontalSizeClass == .compact ? .stack : .columns
    }
}
