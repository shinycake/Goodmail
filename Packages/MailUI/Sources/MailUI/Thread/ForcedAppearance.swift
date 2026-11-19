import Foundation

/// A page laid out in one appearance whatever the system's. A web view that isn't in a window ignores
/// `overrideUserInterfaceStyle` and follows the system's appearance, so the PDF's off-screen pages say theirs in the
/// document and script themselves: every `prefers-color-scheme` query, the sender's and ours, is rewritten to a query
/// that always or never matches, and the root's `color-scheme` is pinned so `light-dark()` and system colors follow.
nonisolated enum ForcedAppearance: Sendable {
    case light
    case dark

    /// `html`, or a script, with each `prefers-color-scheme` test answered for this appearance.
    func apply(to html: String) -> String {
        // The page always has a width, so `min-width: 0px` always matches and `max-width: 0px` never does.
        let (dark, light) = self == .dark ? ("min-width: 0px", "max-width: 0px") : ("max-width: 0px", "min-width: 0px")
        return
            html
            .replacingOccurrences(
                of: #"prefers-color-scheme\s*:\s*dark"#, with: dark, options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"prefers-color-scheme\s*:\s*light"#, with: light, options: [.regularExpression, .caseInsensitive])
    }

    /// Pins the root's color scheme, over the palette's and the sender's.
    var rootStyle: String {
        switch self {
        case .light: "<style>:root { color-scheme: light !important; }</style>"
        case .dark: "<style>:root { color-scheme: dark !important; }</style>"
        }
    }
}
