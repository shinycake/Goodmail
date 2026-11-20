import MailCore
import UIKit

nonisolated extension UIColor {
    /// A button filled with this color, as `ButtonShade` draws it for the appearance it's shown in: a deep shade in
    /// dark mode, a pale tint in light mode.
    var shadedFill: UIColor { shaded { $0.fill } }

    /// The symbol on a button filled with `shadedFill`: white in dark mode, a deep shade of this color in light mode.
    var shadedSymbol: UIColor { shaded { $0.symbol } }

    private func shaded(_ part: @escaping @Sendable (ButtonShade) -> MailCore.RGBColor) -> UIColor {
        UIColor { [self] traits in
            let (red, green, blue, _) = resolvedColor(with: traits).rgba
            let picked = MailCore.RGBColor(fractionalRed: Double(red), green: Double(green), blue: Double(blue))
            let appearance: Appearance = traits.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(part(ButtonShade(for: picked, in: appearance)))
        }
    }
}
