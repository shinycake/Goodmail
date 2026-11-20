import Foundation

/// A color as hue (0 to 1 around the wheel), saturation and lightness.
struct HSL {
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }

    func with(lightness: Double) -> HSL {
        HSL(hue: hue, saturation: saturation, lightness: lightness)
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
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
