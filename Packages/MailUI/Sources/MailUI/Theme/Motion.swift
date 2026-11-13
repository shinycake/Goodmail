import UIKit

/// Animation choices that follow the Reduce Motion setting. Springs keep their timing but lose their overshoot,
/// and movement that only decorates a change gives way to a plain fade.
enum Motion {
    /// `bounce`, or none when Reduce Motion is on.
    static func bounce(_ bounce: CGFloat) -> CGFloat {
        UIAccessibility.isReduceMotionEnabled ? 0 : bounce
    }

    /// Where a view slides in from: `transform`, or where it already is when Reduce Motion is on.
    static func entrance(_ transform: CGAffineTransform) -> CGAffineTransform {
        UIAccessibility.isReduceMotionEnabled ? .identity : transform
    }
}
