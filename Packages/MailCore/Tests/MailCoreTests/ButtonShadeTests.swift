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

    @Test(arguments: picks)
    func darkModeWearsADeepShadeWithAWhiteSymbol(pick: RGBColor) {
        let shade = ButtonShade(for: pick, in: .dark)
        #expect(shade.symbol == RGBColor(red: 255, green: 255, blue: 255))
        #expect(shade.fill.contrastRatio(with: shade.symbol) >= ButtonShade.minimumContrast)
        #expect(shade.fill.lightness <= ButtonShade.darkLightness.upperBound + 0.01)
    }

    @Test(arguments: picks)
    func lightModeWearsAPaleTintWithADeepSymbol(pick: RGBColor) {
        let shade = ButtonShade(for: pick, in: .light)
        #expect(shade.fill.lightness >= ButtonShade.lightLightness.lowerBound - 0.01)
        #expect(shade.fill.contrastRatio(with: shade.symbol) >= ButtonShade.minimumContrast)
        #expect(shade.symbol.lightness < shade.fill.lightness)
    }

    @Test(arguments: picks)
    func darkShadesStayVisibleOnABlackList(pick: RGBColor) {
        #expect(ButtonShade(for: pick, in: .dark).fill.lightness >= ButtonShade.darkLightness.lowerBound - 0.01)
    }

    @Test func aShadeKeepsThePicksHue() {
        let green = RGBColor(red: 0x34, green: 0xC7, blue: 0x59)
        for appearance in [Appearance.light, .dark] {
            let shade = ButtonShade(for: green, in: appearance)
            #expect(shade.fill.green > shade.fill.red)
            #expect(shade.fill.green > shade.fill.blue)
        }
        let symbol = ButtonShade(for: green, in: .light).symbol
        #expect(symbol.green > symbol.red && symbol.green > symbol.blue)
    }

    @Test func aDeepPickAlreadyInRangeIsLeftAsItIsInDarkMode() {
        let maroon = RGBColor(red: 0x6B, green: 0x1A, blue: 0x1F)
        #expect(ButtonShade(for: maroon, in: .dark).fill == maroon)
    }

    @Test func aGrayPickStaysGray() {
        let shade = ButtonShade(for: RGBColor(red: 0x80, green: 0x80, blue: 0x80), in: .light)
        #expect(shade.fill.red == shade.fill.green && shade.fill.green == shade.fill.blue)
        #expect(shade.symbol.red == shade.symbol.green && shade.symbol.green == shade.symbol.blue)
    }
}
