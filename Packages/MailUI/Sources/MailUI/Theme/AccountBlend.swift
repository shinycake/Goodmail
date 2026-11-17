public import MailCore
public import UIKit

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

    /// This gradient in `traits`' colors, laid from left (0) to right (1) so it runs from the leading edge in
    /// `direction` to the trailing one.
    func gradient(in traits: UITraitCollection, direction: UIUserInterfaceLayoutDirection) -> CGGradient? {
        let leading = direction == .rightToLeft ? Array(gradientStops.reversed()) : gradientStops
        return Self.gradient(
            leading.map { $0.color.uiColor.resolvedColor(with: traits).cgColor },
            at: gradientStops.map { CGFloat($0.location) })
    }

    /// `symbol` painted in this gradient from its leading edge to its trailing one, in `traits`' colors. A symbol's
    /// tint takes one plain color, so the gradient is drawn into the image, keeping how the symbol sits on a line.
    func paint(_ symbol: UIImage, in traits: UITraitCollection, direction: UIUserInterfaceLayoutDirection) -> UIImage {
        let bounds = CGRect(origin: .zero, size: symbol.size)
        let painted = UIGraphicsImageRenderer(bounds: bounds, format: UIGraphicsImageRendererFormat(for: traits))
            .image { context in
                symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: bounds)
                guard let gradient = gradient(in: traits, direction: direction) else { return }
                // Only where the symbol is drawn.
                context.cgContext.setBlendMode(.sourceIn)
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: bounds.width, y: 0), options: [])
            }
        return painted.withBaselineOffset(fromBottom: symbol.baselineOffsetFromBottom ?? 0)
            .withAlignmentRectInsets(symbol.alignmentRectInsets).withRenderingMode(.alwaysOriginal)
    }

    /// A gradient through `colors` at `locations`, in extended sRGB.
    private static func gradient(_ colors: [CGColor], at locations: [CGFloat]) -> CGGradient? {
        // Unsafe because the locations pass as a pointer. Safe: CGGradient copies them before it returns.
        unsafe CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.extendedSRGB), colors: colors as CFArray, locations: locations)
    }
}
