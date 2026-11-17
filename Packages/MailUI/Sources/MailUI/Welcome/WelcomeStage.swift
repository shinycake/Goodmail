import SwiftUI

/// The middle of the welcome screen: the envelopes with the welcome doodles around them.
struct WelcomeStage: View {
    let envelopeWidth: CGFloat

    var body: some View {
        DoodleStage(doodles: Doodle.welcome, envelopeWidth: envelopeWidth)
    }
}
