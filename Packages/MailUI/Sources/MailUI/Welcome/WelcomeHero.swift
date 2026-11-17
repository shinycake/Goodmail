import SwiftUI

/// The top of the welcome screen: the envelopes on their stage, which takes all the height the buttons leave, and
/// the app's name under it.
struct WelcomeHero: View {
    /// On a short screen the envelopes are smaller and the spacing tighter.
    let isShort: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var envelopeWidth = 280
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: isShort ? 12 : 20) {
            WelcomeStage(envelopeWidth: width)
                .frame(maxWidth: .infinity, minHeight: width * WelcomeEnvelope.aspect + room, maxHeight: .infinity)
            Text(
                "Welcome to Goodmail", tableName: "Welcome", bundle: .module,
                comment: "The welcome screen's title, shown before any account is added"
            )
            .font(.largeTitle.bold())
            // A headline this short stays legible at the second accessibility size, and growing it further only
            // pushes the buttons off screen.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
            // Narrower margins than the buttons', so the English title keeps to one line on the narrowest iPhone.
            .padding(.horizontal, 8)
        }
        // Keeps the doodles along the top of the stage off the status bar.
        .padding(.top, 12)
    }

    /// Grows with the text size, but stays small enough at accessibility sizes to leave the screen to the buttons.
    private var width: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 150 }
        return isShort ? envelopeWidth * 0.7 : min(envelopeWidth, 310)
    }

    /// The least height the stage keeps around the envelopes, for when the screen is too short to give it more.
    private var room: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 32 }
        return isShort ? 56 : 96
    }
}

/// A soft wash of the icon's blue and purple behind the top of the screen, fading into the system background.
/// Plain background with Reduce Transparency on.
struct WelcomeBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: WelcomePalette.blue.opacity(0.16), location: 0),
                .init(color: WelcomePalette.purple.opacity(0.08), location: 0.35),
                .init(color: .clear, location: 0.7),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .opacity(reduceTransparency ? 0 : 1)
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea()
    }
}
