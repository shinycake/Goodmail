import Foundation

/// Whether the interface is light or dark.
public enum Appearance: Hashable, Sendable {
    case light
    case dark
}

/// How a button filled with a picked color is drawn, so any pick suits the appearance: in dark mode a deep, slightly
/// muted shade under a white symbol; in light mode a pale tint under a deep symbol of the same hue. Either way the
/// symbol stands out from the fill by `minimumContrast`.
public struct ButtonShade: Hashable, Sendable {
    public let fill: RGBColor
    public let symbol: RGBColor

    /// WCAG AA for text, so a full swipe's title reads as well as its symbol.
    public static let minimumContrast = 4.5
    /// The lightness a dark-mode fill is brought into: deep, but never lost on a black list.
    static let darkLightness = 0.18...0.32
    /// The lightness a light-mode fill is brought into: a pale tint that still shows its hue.
    static let lightLightness = 0.86...0.93
    /// How much of its saturation a dark-mode fill keeps, so a vivid pick doesn't glare.
    private static let darkSaturation = 0.85
    /// How deep a light-mode symbol starts, before it darkens further for contrast.
    private static let lightSymbolLightness = 0.32
    private static let white = RGBColor(red: 255, green: 255, blue: 255)

    public init(for color: RGBColor, in appearance: Appearance) {
        let picked = HSL(color)
        switch appearance {
        case .dark:
            let start = HSL(
                hue: picked.hue, saturation: picked.saturation * Self.darkSaturation,
                lightness: picked.lightness.clamped(to: Self.darkLightness))
            // A pick already deep enough keeps its exact color.
            let base = Self.darkLightness.contains(picked.lightness) ? color : start.rgb
            fill = Self.darkened(start, from: base, until: { $0.contrastRatio(with: Self.white) })
            symbol = Self.white
        case .light:
            let tint = HSL(
                hue: picked.hue, saturation: picked.saturation,
                lightness: picked.lightness.clamped(to: Self.lightLightness))
            fill = tint.rgb
            let deep = HSL(
                hue: picked.hue, saturation: picked.saturation,
                lightness: min(picked.lightness, Self.lightSymbolLightness))
            symbol = Self.darkened(deep, from: deep.rgb, until: { [fill] in $0.contrastRatio(with: fill) })
        }
    }

    /// `base`, or `color` darkened step by step, until `contrast` reaches `minimumContrast`; black at worst.
    private static func darkened(_ color: HSL, from base: RGBColor, until contrast: (RGBColor) -> Double)
        -> RGBColor
    {
        var candidate = base
        var lightness = color.lightness
        while contrast(candidate) < minimumContrast, lightness > 0 {
            lightness = max(0, lightness - 0.02)
            candidate = HSL(hue: color.hue, saturation: color.saturation, lightness: lightness).rgb
        }
        return candidate
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

/// A color as hue (0 to 1 around the wheel), saturation and lightness.
private struct HSL {
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }

    init(_ color: RGBColor) {
        let (red, green, blue) = color.components
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let chroma = high - low
        lightness = (high + low) / 2
        saturation = chroma == 0 ? 0 : chroma / (1 - abs(2 * lightness - 1))
        let sector: Double =
            switch high {
            case _ where chroma == 0: 0
            case red: (green - blue) / chroma
            case green: (blue - red) / chroma + 2
            default: (red - green) / chroma + 4
            }
        hue = (sector / 6).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
    }

    var rgb: RGBColor {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue * 6
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double) =
            switch Int(sector) % 6 {
            case 0: (chroma, second, 0)
            case 1: (second, chroma, 0)
            case 2: (0, chroma, second)
            case 3: (0, second, chroma)
            case 4: (second, 0, chroma)
            default: (chroma, 0, second)
            }
        let offset = lightness - chroma / 2
        return RGBColor(fractionalRed: red + offset, green: green + offset, blue: blue + offset)
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
