import Foundation

/// CSS colors as SVG uses them: `#rgb`, `#rrggbb`, `rgb()`, `rgba()` and the common keywords.
enum SVGColor {
    /// A `fill` or `stroke` value, or `nil` when it can't be read, which leaves the inherited paint.
    static func paint(_ value: String) -> SVGPaintSpec? {
        let value = value.trimmingCharacters(in: .whitespaces)
        switch value.lowercased() {
        case "none", "transparent": return SVGPaintSpec.none
        case "currentcolor": return .currentColor
        default: break
        }
        if value.hasPrefix("url(") {
            guard let close = value.firstIndex(of: ")") else { return nil }
            var target = value[value.index(value.startIndex, offsetBy: 4)..<close]
                .trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            guard target.hasPrefix("#") else { return nil }
            target.removeFirst()
            let fallback = value[value.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return .reference(target, fallback: color(fallback))
        }
        return color(value).map(SVGPaintSpec.color)
    }

    static func color(_ value: String) -> VectorColor? {
        let value = value.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") { return hex(value.dropFirst()) }
        if value.hasPrefix("rgb") { return functional(value) }
        return named[value]
    }

    private static func hex(_ digits: Substring) -> VectorColor? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let values = digits.compactMap { $0.hexDigitValue.map(Double.init) }
        switch values.count {
        case 3, 4:
            let alpha = values.count == 4 ? values[3] / 15 : 1
            return VectorColor(red: values[0] / 15, green: values[1] / 15, blue: values[2] / 15, alpha: alpha)
        case 6, 8:
            func byte(_ index: Int) -> Double { (values[index] * 16 + values[index + 1]) / 255 }
            return VectorColor(red: byte(0), green: byte(2), blue: byte(4), alpha: values.count == 8 ? byte(6) : 1)
        default: return nil
        }
    }

    /// `rgb(255, 0, 0)`, `rgb(100%, 0%, 0%)` and `rgba(…, 0.5)`, with commas or spaces.
    private static func functional(_ value: String) -> VectorColor? {
        guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")") else { return nil }
        let parts = value[value.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        func channel(_ text: String) -> Double? {
            text.hasSuffix("%")
                ? Double(text.dropLast()).map { $0 / 100 } : Double(text).map { $0 / 255 }
        }
        guard let red = channel(parts[0]), let green = channel(parts[1]), let blue = channel(parts[2]) else {
            return nil
        }
        let alpha = parts.count == 4 ? SVGStyle.fraction(parts[3]) ?? 1 : 1
        func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
        return VectorColor(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: alpha)
    }

    /// SVG Tiny's sixteen keywords, and a few more that exporters write.
    private static let named: [String: VectorColor] = [
        "black": rgb(0, 0, 0), "silver": rgb(192, 192, 192), "gray": rgb(128, 128, 128), "grey": rgb(128, 128, 128),
        "white": rgb(255, 255, 255), "maroon": rgb(128, 0, 0), "red": rgb(255, 0, 0), "purple": rgb(128, 0, 128),
        "fuchsia": rgb(255, 0, 255), "green": rgb(0, 128, 0), "lime": rgb(0, 255, 0), "olive": rgb(128, 128, 0),
        "yellow": rgb(255, 255, 0), "navy": rgb(0, 0, 128), "blue": rgb(0, 0, 255), "teal": rgb(0, 128, 128),
        "aqua": rgb(0, 255, 255), "orange": rgb(255, 165, 0), "darkgray": rgb(169, 169, 169),
        "lightgray": rgb(211, 211, 211), "darkblue": rgb(0, 0, 139), "darkred": rgb(139, 0, 0),
        "darkgreen": rgb(0, 100, 0), "gold": rgb(255, 215, 0), "pink": rgb(255, 192, 203),
    ]

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> VectorColor {
        VectorColor(red: red / 255, green: green / 255, blue: blue / 255)
    }
}
