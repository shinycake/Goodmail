import UIKit

extension UIColor {
    /// The WCAG 2 contrast ratio between this color and `other`, from 1 (none) to 21 (black on white), both as
    /// resolved for `traits`.
    func contrastRatio(with other: UIColor, in traits: UITraitCollection) -> CGFloat {
        let mine = resolvedColor(with: traits).relativeLuminance
        let theirs = other.resolvedColor(with: traits).relativeLuminance
        return (max(mine, theirs) + 0.05) / (min(mine, theirs) + 0.05)
    }

    /// WCAG 2 relative luminance of an already resolved color. Extended-range components are clamped to sRGB.
    private var relativeLuminance: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ component: CGFloat) -> CGFloat {
            let value = min(max(component, 0), 1)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
