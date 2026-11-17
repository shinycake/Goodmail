import SwiftUI

/// The app icon's three envelope colors, for the doodles around them.
enum DoodlePalette {
    static let blue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let purple = Color(red: 0.69, green: 0.32, blue: 0.87)
    static let pink = Color(red: 1.0, green: 0.18, blue: 0.33)

    static let all = [blue, purple, pink]

    /// The colors washed `amount` of the way into `background`: mixed, not see-through, so they look the same with
    /// Reduce Transparency on.
    static func washed(into background: Color, by amount: Double) -> [Color] {
        all.map { $0.mix(with: background, by: amount) }
    }
}
