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
        case .blue: String(localized: "Blue", bundle: .module, comment: "An account color")
        case .indigo: String(localized: "Indigo", bundle: .module, comment: "An account color")
        case .purple: String(localized: "Purple", bundle: .module, comment: "An account color")
        case .pink: String(localized: "Pink", bundle: .module, comment: "An account color")
        case .orange: String(localized: "Orange", bundle: .module, comment: "An account color")
        case .yellow: String(localized: "Yellow", bundle: .module, comment: "An account color")
        case .green: String(localized: "Green", bundle: .module, comment: "An account color")
        case .mint: String(localized: "Mint", bundle: .module, comment: "An account color")
        case .teal: String(localized: "Teal", bundle: .module, comment: "An account color")
        case .cyan: String(localized: "Cyan", bundle: .module, comment: "An account color")
        case .brown: String(localized: "Brown", bundle: .module, comment: "An account color")
        case .graphite: String(localized: "Graphite", bundle: .module, comment: "An account color")
        }
    }
}
