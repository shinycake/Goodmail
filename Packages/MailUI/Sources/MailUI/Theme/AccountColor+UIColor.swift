import MailCore
import UIKit

extension AccountColor {
    /// System colors, so every account color adapts to dark mode and Increase Contrast for free.
    public var uiColor: UIColor {
        switch self {
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .cyan: .systemCyan
        case .brown: .systemBrown
        case .graphite: .systemGray
        }
    }

    /// The color's name, for VoiceOver.
    var title: String {
        switch self {
        case .blue: String(localized: "Blue", table: "Theme", bundle: .module, comment: "An account color")
        case .indigo: String(localized: "Indigo", table: "Theme", bundle: .module, comment: "An account color")
        case .purple: String(localized: "Purple", table: "Theme", bundle: .module, comment: "An account color")
        case .pink: String(localized: "Pink", table: "Theme", bundle: .module, comment: "An account color")
        case .orange: String(localized: "Orange", table: "Theme", bundle: .module, comment: "An account color")
        case .yellow: String(localized: "Yellow", table: "Theme", bundle: .module, comment: "An account color")
        case .green: String(localized: "Green", table: "Theme", bundle: .module, comment: "An account color")
        case .mint: String(localized: "Mint", table: "Theme", bundle: .module, comment: "An account color")
        case .teal: String(localized: "Teal", table: "Theme", bundle: .module, comment: "An account color")
        case .cyan: String(localized: "Cyan", table: "Theme", bundle: .module, comment: "An account color")
        case .brown: String(localized: "Brown", table: "Theme", bundle: .module, comment: "An account color")
        case .graphite: String(localized: "Graphite", table: "Theme", bundle: .module, comment: "An account color")
        }
    }
}
