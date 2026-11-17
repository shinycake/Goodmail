import SwiftUI

/// A service's button on the welcome screen: the name centered across the full width, and the logo at the leading
/// edge, so every button is the same width and the logos line up down the stack. At accessibility text sizes the
/// name leads from beside the logo instead, so it keeps the most width and doesn't break mid-word.
struct WelcomeServiceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        WelcomeServiceLabel(configuration: configuration)
    }
}

private struct WelcomeServiceLabel: View {
    let configuration: LabelStyleConfiguration
    /// Matches the logo's side, so the name keeps clear of it at every text size.
    @ScaledMetric(relativeTo: .body) private var iconSide = 24
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The logo leads and the name wraps beside it, between words, filling the rest of the width.
                HStack(spacing: 12) {
                    configuration.icon
                    title.multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            } else {
                title
                    .multilineTextAlignment(.center)
                    // The same inset on both sides keeps the name centered on the button, not on the space beside
                    // the logo.
                    .padding(.horizontal, iconSide + 12)
                    // Full width before the overlay, so every logo sits at the button's edge and they line up.
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) { configuration.icon }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var title: some View {
        configuration.title
            .font(.body.weight(.semibold))
    }
}
