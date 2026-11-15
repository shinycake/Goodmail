/// The theme color an account is shown in: one of the offered system colors, or one the reader picked. Red is not
/// offered: it is reserved for destructive actions.
public enum AccountColor: Hashable, Sendable {
    case blue
    case indigo
    case purple
    case pink
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case brown
    case graphite
    /// A color picked with the system color picker.
    case custom(RGBColor)

    /// The offered colors, in the order they are shown and handed out.
    public static let presets: [AccountColor] = [
        .blue, .indigo, .purple, .pink, .orange, .yellow, .green, .mint, .teal, .cyan, .brown, .graphite,
    ]

    /// The color for a newly added account: the first offered one no existing account uses, cycling once all are
    /// taken.
    public static func next(after used: [AccountColor]) -> AccountColor {
        if let unused = presets.first(where: { !used.contains($0) }) {
            return unused
        }
        return presets[used.count % presets.count]
    }

    /// How the color is stored: an offered color's name, or a picked one's hex string, such as `#3366FF`.
    public var rawValue: String {
        switch self {
        case .blue: "blue"
        case .indigo: "indigo"
        case .purple: "purple"
        case .pink: "pink"
        case .orange: "orange"
        case .yellow: "yellow"
        case .green: "green"
        case .mint: "mint"
        case .teal: "teal"
        case .cyan: "cyan"
        case .brown: "brown"
        case .graphite: "graphite"
        case .custom(let color): color.hex
        }
    }

    /// `nil` for a name no offered color has, or a malformed hex string.
    public init?(rawValue: String) {
        if let preset = Self.presets.first(where: { $0.rawValue == rawValue }) {
            self = preset
        } else if let color = RGBColor(hex: rawValue) {
            self = .custom(color)
        } else {
            return nil
        }
    }
}
