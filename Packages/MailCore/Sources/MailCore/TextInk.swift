import Foundation

/// A text color a writer chose, brought to one that reads for every recipient. A client may show the message on a
/// white page or, in dark mode, on a dark one, and some dark modes keep a fixed color as it is, so the color has to
/// stand out from both. No color reaches 4.5:1 against white and a dark gray at once; 3:1, WCAG's bar for large
/// text, is what both allow. A color that falls short keeps its hue and saturation and moves in lightness until it
/// stands out from both, so a pale yellow sends as a deeper yellow, not as gray.
public struct TextInk: Hashable, Sendable {
    public let color: RGBColor

    static let minimumContrast = 3.0
    static let lightPage = RGBColor(red: 0xFF, green: 0xFF, blue: 0xFF)
    /// The lightest of the dark pages mail apps draw, so the color reads on the darker ones too.
    static let darkPage = RGBColor(red: 0x2C, green: 0x2C, blue: 0x2E)

    public init(_ picked: RGBColor) {
        // A color that already reads stays exactly as picked: an HSL round trip can move a byte.
        guard !Self.readsOnBoth(picked) else {
            color = picked
            return
        }
        var color = HSL(picked)
        // Too light for the white page means it must deepen; otherwise it must brighten.
        let step = picked.contrastRatio(with: Self.lightPage) < Self.minimumContrast ? -0.01 : 0.01
        while !Self.readsOnBoth(color.rgb), (0...1).contains(color.lightness + step) {
            color.lightness += step
        }
        self.color = color.rgb
    }

    private static func readsOnBoth(_ color: RGBColor) -> Bool {
        color.contrastRatio(with: lightPage) >= minimumContrast
            && color.contrastRatio(with: darkPage) >= minimumContrast
    }
}
