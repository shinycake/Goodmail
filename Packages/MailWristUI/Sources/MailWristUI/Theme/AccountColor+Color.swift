public import MailCore
public import SwiftUI

extension AccountColor {
    /// The system color of the same name, so it adapts as the iPhone's does. A picked color shows as picked: the watch
    /// is always dark, and the iPhone already keeps picked colors legible on dark backgrounds.
    public var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .brown: .brown
        case .graphite: .gray
        case .custom(let picked):
            Color(red: Double(picked.red) / 255, green: Double(picked.green) / 255, blue: Double(picked.blue) / 255)
        }
    }
}
