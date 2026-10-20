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
}
