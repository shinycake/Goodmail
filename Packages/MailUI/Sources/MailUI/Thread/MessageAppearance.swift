import UIKit

/// How one open message reads: in the app's appearance, or in light while the app is dark, as Apple Mail lets a
/// reader view one message with a light background. Mail written for a white page often reads better there.
enum MessageAppearance {
    /// The card, its header and its body follow the app.
    case app
    /// The whole card turns light: its header, its body and its sender's own light styles.
    case light

    var switched: MessageAppearance {
        switch self {
        case .app: .light
        case .light: .app
        }
    }

    /// The style the card's surface overrides its traits with. The web view takes `prefers-color-scheme` from it.
    var style: UIUserInterfaceStyle {
        switch self {
        case .app: .unspecified
        case .light: .light
        }
    }

    /// The symbol of the button that switches it: the sun while the message follows the dark app, the moon while it
    /// reads in light.
    var switchSymbol: String {
        switch self {
        case .app: "sun.max"
        case .light: "moon"
        }
    }

    /// What the button that switches it says to VoiceOver and in its tooltip.
    var switchTitle: String {
        switch self {
        case .app:
            String(
                localized: "View in Light Mode", table: "Thread", bundle: .module,
                comment: "Button on an open message in dark mode: shows that one message in light mode")
        case .light:
            String(
                localized: "View in Dark Mode", table: "Thread", bundle: .module,
                comment: "Button on a message shown in light mode: shows it in dark mode again")
        }
    }
}
