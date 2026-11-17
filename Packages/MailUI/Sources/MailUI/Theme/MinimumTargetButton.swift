import UIKit

/// A button drawn as small as its text, as an inline Details link is, that still takes touches and VoiceOver's
/// focus over the 44-point square the HIG asks of every control.
final class MinimumTargetButton: UIButton {
    static let minimumSide: CGFloat = 44

    /// The bounds grown to the minimum side around their middle, never shrunk.
    private var targetBounds: CGRect {
        bounds.insetBy(
            dx: min(0, (bounds.width - Self.minimumSide) / 2), dy: min(0, (bounds.height - Self.minimumSide) / 2))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        targetBounds.contains(point)
    }

    override var accessibilityFrame: CGRect {
        get { SystemAccessibility.screenFrame(of: targetBounds, in: self) }
        set { super.accessibilityFrame = newValue }
    }
}
