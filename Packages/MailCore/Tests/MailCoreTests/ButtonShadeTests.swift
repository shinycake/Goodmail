import Foundation
import Testing

@testable import MailCore

struct ButtonShadeTests {
    /// Colors a reader might pick, from the system's own to the extremes of the picker.
    static let picks: [RGBColor] = [
        RGBColor(red: 0xFF, green: 0x3B, blue: 0x30),  // system red
        RGBColor(red: 0x34, green: 0xC7, blue: 0x59),  // system green
        RGBColor(red: 0xFF, green: 0xCC, blue: 0x00),  // yellow
        RGBColor(red: 0x00, green: 0x7A, blue: 0xFF),  // blue
        RGBColor(red: 0x6B, green: 0x1A, blue: 0x1F),  // maroon
        RGBColor(red: 0x00, green: 0x00, blue: 0x00),  // black
        RGBColor(red: 0xFF, green: 0xFF, blue: 0xFF),  // white
        RGBColor(red: 0x80, green: 0x80, blue: 0x80),  // gray
        RGBColor(red: 0xF0, green: 0xF0, blue: 0x10),  // pale yellow
    ]

    @Test func contrastRunsFromOneToTwentyOne() {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 255, green: 255, blue: 255)
        #expect(black.contrastRatio(with: white) == 21)
        #expect(white.contrastRatio(with: white) == 1)
        #expect(black.contrastRatio(with: white) == white.contrastRatio(with: black))
    }

    @Test(arguments: picks, [Appearance.light, .dark])
    func theSymbolStandsOutFromTheFill(pick: RGBColor, appearance: Appearance) {
        let shade = ButtonShade(for: pick, in: appearance)
        #expect(shade.fill.contrastRatio(with: shade.symbol) >= ButtonShade.minimumContrast)
    }

    @Test(arguments: picks)
    func darkModeWearsADeepTintUnderABrightSymbol(pick: RGBColor) {
        let shade = ButtonShade(for: pick, in: .dark)
        #expect(ButtonShade.darkLightness.contains(shade.fill.lightness.rounded(toPlaces: 2)))
        #expect(shade.symbol.lightness > shade.fill.lightness)
    }

    @Test(arguments: picks)
    func lightModeWearsAPaleTintUnderADeepSymbol(pick: RGBColor) {
        let shade = ButtonShade(for: pick, in: .light)
        #expect(ButtonShade.lightLightness.contains(shade.fill.lightness.rounded(toPlaces: 2)))
        #expect(shade.symbol.lightness < shade.fill.lightness)
    }

    @Test(arguments: [Appearance.light, .dark])
    func aShadeKeepsThePicksHue(appearance: Appearance) {
        let green = RGBColor(red: 0x34, green: 0xC7, blue: 0x59)
        let shade = ButtonShade(for: green, in: appearance)
        for color in [shade.fill, shade.symbol] {
            #expect(color.green > color.red && color.green > color.blue)
        }
    }

    @Test func aGrayPickStaysGray() {
        let shade = ButtonShade(for: RGBColor(red: 0x80, green: 0x80, blue: 0x80), in: .light)
        #expect(shade.fill.red == shade.fill.green && shade.fill.green == shade.fill.blue)
        #expect(shade.symbol.red == shade.symbol.green && shade.symbol.green == shade.symbol.blue)
    }
}

extension Double {
    fileprivate func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
