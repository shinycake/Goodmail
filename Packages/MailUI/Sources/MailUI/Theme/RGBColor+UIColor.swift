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
        var mine = (red: CGFloat(0), green: CGFloat(0), blue: CGFloat(0), alpha: CGFloat(0))
        var theirs = mine
        getRed(&mine.red, green: &mine.green, blue: &mine.blue, alpha: &mine.alpha)
        other.getRed(&theirs.red, green: &theirs.green, blue: &theirs.blue, alpha: &theirs.alpha)
        func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * fraction }
        return UIColor(
            red: mix(mine.red, theirs.red), green: mix(mine.green, theirs.green), blue: mix(mine.blue, theirs.blue),
            alpha: mine.alpha)
    }
}
