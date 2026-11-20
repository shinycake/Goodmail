import Foundation

/// Whether the interface is light or dark.
public enum Appearance: Hashable, Sendable {
    case light
    case dark
}

/// How a button filled with a picked color is drawn, so any pick suits the appearance: a tint of the pick under a
/// symbol in the same hue. In light mode the tint is pale and the symbol deep; in dark mode the tint is deep and the
/// symbol bright. Either way the symbol stands out from the fill by `minimumContrast`.
public struct ButtonShade: Hashable, Sendable {
    public let fill: RGBColor
    public let symbol: RGBColor

    /// WCAG AA for text, so a full swipe's title reads as well as its symbol.
    public static let minimumContrast = 4.5
    /// The lightness a dark-mode fill is brought into: a deep tint that still shows on a black list.
    static let darkLightness = 0.16...0.24
    /// The lightness a light-mode fill is brought into: a pale tint that still shows its hue.
    static let lightLightness = 0.86...0.93
    /// How bright a dark-mode symbol is at least, before it lightens further for contrast.
    private static let darkSymbolLightness = 0.68
    /// How deep a light-mode symbol is at most, before it darkens further for contrast.
    private static let lightSymbolLightness = 0.32

    public init(for color: RGBColor, in appearance: Appearance) {
        let picked = HSL(color)
        let (fillRange, symbolStart, step): (ClosedRange<Double>, Double, Double) =
            switch appearance {
            case .dark: (Self.darkLightness, max(picked.lightness, Self.darkSymbolLightness), 0.02)
            case .light: (Self.lightLightness, min(picked.lightness, Self.lightSymbolLightness), -0.02)
            }
        let fill = picked.with(lightness: picked.lightness.clamped(to: fillRange)).rgb
        var symbol = picked.with(lightness: symbolStart)
        // Brightens a dark-mode symbol, or deepens a light-mode one, until it stands out; white or black at worst.
        while symbol.rgb.contrastRatio(with: fill) < Self.minimumContrast, (0...1).contains(symbol.lightness + step) {
            symbol.lightness += step
        }
        self.fill = fill
        self.symbol = symbol.rgb
    }
}

extension RGBColor {
    /// WCAG 2 relative luminance, from 0 (black) to 1 (white).
    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let (red, green, blue) = components
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG 2 contrast ratio with `other`, from 1 (none) to 21 (black on white).
    public func contrastRatio(with other: RGBColor) -> Double {
        let (high, low) = (
            max(relativeLuminance, other.relativeLuminance), min(relativeLuminance, other.relativeLuminance)
        )
        return (high + 0.05) / (low + 0.05)
    }

    /// HSL lightness, from 0 (black) to 1 (white).
    var lightness: Double { HSL(self).lightness }
}
