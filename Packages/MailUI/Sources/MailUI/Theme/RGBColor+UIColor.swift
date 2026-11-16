import MailCore
import UIKit

extension UIColor {
    /// The picked color exactly, in both light and dark mode.
    nonisolated convenience init(_ color: RGBColor) {
        let components = color.components
        self.init(red: components.red, green: components.green, blue: components.blue, alpha: 1)
    }

    /// This color, moved toward the label color in steps until it stands out from the background by
    /// `AccountBlend.legibleContrast`, or by 4.5 with Increase Contrast on: so a dark pick still reads in dark mode
    /// and a pale one in light mode. A color that already stands out is left as it is.
    var legibleOnBackground: UIColor {
        UIColor { [self] traits in
            let color = resolvedColor(with: traits)
            let minimum: CGFloat = traits.accessibilityContrast == .high ? 4.5 : AccountBlend.legibleContrast
            let toward: UIColor = traits.userInterfaceStyle == .dark ? .white : .black
            let steps = 10
            for step in 0...steps {
                let mixed = color.mixed(with: toward, by: CGFloat(step) / CGFloat(steps))
                if mixed.contrastRatio(with: .systemBackground, in: traits) >= minimum { return mixed }
            }
            return toward
        }
    }

    /// Both already resolved: `fraction` of the way from this color to `other`, channel by channel.
    private func mixed(with other: UIColor, by fraction: CGFloat) -> UIColor {
        let (mine, theirs) = (rgba, other.rgba)
        func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * fraction }
        return UIColor(
            red: mix(mine.red, theirs.red), green: mix(mine.green, theirs.green), blue: mix(mine.blue, theirs.blue),
            alpha: mine.alpha)
    }
}

nonisolated extension UIColor {
    /// The components of an already resolved color, in the extended sRGB space. The one caller of
    /// `getRed(_:green:blue:alpha:)`, so the pointers it writes through stay here.
    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        // Unsafe because it writes through pointers. Safe: each points at a local that outlives the call.
        _ = unsafe getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
}
