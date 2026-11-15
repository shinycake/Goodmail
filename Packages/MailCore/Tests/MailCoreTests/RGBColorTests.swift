import Testing

@testable import MailCore

struct RGBColorTests {
    @Test func hexRoundTrips() {
        let color = RGBColor(red: 0x0A, green: 0xB0, blue: 0xFF)
        #expect(color.hex == "#0AB0FF")
        #expect(RGBColor(hex: color.hex) == color)
    }

    @Test(arguments: ["", "#", "0AB0FF", "#0AB0F", "#0AB0FF0", "#GGGGGG", "#-1B0FF", "#+1B0FF", "blue"])
    func malformedHexIsRejected(hex: String) {
        #expect(RGBColor(hex: hex) == nil)
    }

    @Test func pickerComponentsRoundToBytes() {
        #expect(RGBColor(fractionalRed: 1, green: 0.5, blue: 0) == RGBColor(red: 255, green: 128, blue: 0))
    }

    @Test func wideGamutComponentsAreClamped() {
        #expect(RGBColor(fractionalRed: 1.2, green: -0.1, blue: 0.2) == RGBColor(red: 255, green: 0, blue: 51))
    }

    @Test func componentsRunFromZeroToOne() {
        let components = RGBColor(red: 255, green: 0, blue: 51).components
        #expect(components.red == 1)
        #expect(components.green == 0)
        #expect(components.blue == 0.2)
    }
}
