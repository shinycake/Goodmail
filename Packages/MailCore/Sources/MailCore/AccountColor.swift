/// The theme color an account is shown in. Red is not offered: it is reserved for destructive actions.
public enum AccountColor: String, CaseIterable, Codable, Sendable {
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

    /// The color for a newly added account: the first one no existing account uses, cycling once all are taken.
    public static func next(after used: [AccountColor]) -> AccountColor {
        if let unused = allCases.first(where: { !used.contains($0) }) {
            return unused
        }
        return allCases[used.count % allCases.count]
    }
}
