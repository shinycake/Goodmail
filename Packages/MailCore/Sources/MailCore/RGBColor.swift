/// A color the reader picked themselves, as 8-bit sRGB, so it reads back exactly as it was stored. It is written as
/// a hex string, such as `#3366FF`.
public struct RGBColor: Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Components from 0 to 1, as a color picker gives them. Ones outside that range, as from a wide-gamut color,
    /// are clamped to it.
    public init(fractionalRed red: Double, green: Double, blue: Double) {
        func byte(_ component: Double) -> UInt8 {
            UInt8((min(max(component, 0), 1) * 255).rounded())
        }
        self.init(red: byte(red), green: byte(green), blue: byte(blue))
    }

    /// Reads `#RRGGBB`, in either case; `nil` for anything else.
    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy(\.isHexDigit),
            let value = UInt32(hex.dropFirst(), radix: 16)
        else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// `#RRGGBB`, in capitals.
    public var hex: String {
        "#"
            + [red, green, blue].map { byte in
                let digits = String(byte, radix: 16, uppercase: true)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
    }

    /// The components from 0 to 1.
    public var components: (red: Double, green: Double, blue: Double) {
        (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
    }
}
