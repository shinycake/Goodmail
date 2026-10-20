import MailCore
import UIKit

/// The theme of a view that spans several accounts, such as the unified inbox: a gradient through every
/// account's color, and one blended tint for controls.
public struct AccountBlend: Equatable {
    public struct Stop: Equatable {
        public let color: AccountColor
        public let location: Double
    }

    /// Distinct colors, in account order.
    public let colors: [AccountColor]

    public init(_ colors: [AccountColor]) {
        var seen = Set<AccountColor>()
        self.colors = colors.filter { seen.insert($0).inserted }
    }

    /// Evenly spaced from 0 to 1. A single color is a flat two-stop gradient.
    public var gradientStops: [Stop] {
        switch colors.count {
        case 0: []
        case 1: [Stop(color: colors[0], location: 0), Stop(color: colors[0], location: 1)]
        default:
            colors.enumerated().map { index, color in
                Stop(color: color, location: Double(index) / Double(colors.count - 1))
            }
        }
    }

    /// The average of the account colors, resolved per trait collection. The system tint when there are none.
    public var tint: UIColor {
        guard colors.count > 1 else { return colors.first?.uiColor ?? .tintColor }
        let colors = colors.map(\.uiColor)
        return UIColor { traits in
            var sum: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0, 0, 0)
            for color in colors {
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                sum = (sum.red + red, sum.green + green, sum.blue + blue)
            }
            let count = CGFloat(colors.count)
            return UIColor(red: sum.red / count, green: sum.green / count, blue: sum.blue / count, alpha: 1)
        }
    }
}
