import MailCore
import UIKit

/// The theme of a view that spans several accounts, such as the unified inbox: a gradient through every
/// account's color on its title, and one of those colors, the most legible, for its controls.
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

    /// The minimum contrast against the background for a control's tint (WCAG 2, non-text and large text).
    static let legibleContrast: CGFloat = 3

    /// The tint for controls, which take one color: per trait collection, the first account color that stands
    /// out from the background by `legibleContrast`, or the one that stands out most when none does. A gradient
    /// of yellow and blue tints its buttons blue in light mode, where yellow on white is hard to read, and yellow
    /// in dark mode. The system tint when there are no accounts.
    public var tint: UIColor {
        guard colors.count > 1 else { return colors.first?.uiColor ?? .tintColor }
        let colors = colors.map(\.uiColor)
        return UIColor { traits in
            let contrasts = colors.map { (color: $0, ratio: $0.contrastRatio(with: .systemBackground, in: traits)) }
            let legible =
                contrasts.first { $0.ratio >= Self.legibleContrast } ?? contrasts.max { $0.ratio < $1.ratio }
            return (legible?.color ?? .tintColor).resolvedColor(with: traits)
        }
    }

    /// A color that paints text in this gradient, from its leading edge to its trailing one, for text `width`
    /// points wide drawn from the origin of its view. It is a pattern that tiles sideways, so it runs the gradient
    /// out and back again: wherever the text actually starts, it never shows a seam.
    func textColor(width: CGFloat, direction: UIUserInterfaceLayoutDirection) -> UIColor {
        let leading =
            direction == .rightToLeft
            ? gradientStops.reversed().map { Stop(color: $0.color, location: 1 - $0.location) } : gradientStops
        // Out over the first half of the tile, back over the second.
        let stops =
            leading.map { Stop(color: $0.color, location: $0.location / 2) }
            + leading.reversed().map { Stop(color: $0.color, location: 1 - $0.location / 2) }
        let size = CGSize(width: max(ceil(width), 1) * 2, height: 1)
        return UIColor { traits in
            let image = UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: traits)).image {
                context in
                let colors = stops.map { $0.color.uiColor.resolvedColor(with: traits).cgColor }
                guard
                    let gradient = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.extendedSRGB), colors: colors as CFArray,
                        locations: stops.map { CGFloat($0.location) })
                else { return }
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }
            return UIColor(patternImage: image)
        }
    }
}
