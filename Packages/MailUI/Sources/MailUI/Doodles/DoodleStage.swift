import SwiftUI

/// The app icon's envelopes with mail doodles around them. It is alive to touch: a tap anywhere sends a paper plane
/// off from under the finger, pushes the doodles aside and makes the envelopes hop, and the envelopes can be dragged
/// about. With Reduce Motion on it all holds still, and at accessibility text sizes only the envelopes are left.
struct DoodleStage: View {
    /// Where the doodles rest around the envelopes.
    let doodles: [Doodle]
    let envelopeWidth: CGFloat
    @State private var pokes = DoodlePokes()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            // The schedule follows the display, so nothing is drawn while the app is in the background.
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
                let scene = DoodleScene(
                    size: proxy.size, pokes: pokes.live, clock: reduceMotion ? .stopped : .running(timeline.date),
                    rightToLeft: layoutDirection == .rightToLeft)
                // At accessibility sizes the stage is only as tall as the envelopes, and they have it to themselves.
                let isDecorated = !dynamicTypeSize.isAccessibilitySize
                ZStack {
                    if isDecorated {
                        DoodleField(doodles: doodles, scene: scene)
                    }
                    EnvelopePile(width: envelopeWidth, fan: scene.fan)
                        .offset(y: -scene.lift)
                    if isDecorated {
                        PaperPlanes(scene: scene)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .contentShape(.rect)
            .onTapGesture { location in
                let fromCenter = CGSize(
                    width: location.x - proxy.size.width / 2, height: location.y - proxy.size.height / 2)
                pokes.land(offset: fromCenter, time: .now)
            }
        }
        // The stage opens the way a tap on the envelopes plays, a moment after it appears.
        .onAppear { pokes.land(offset: .zero, time: .now + 0.6) }
        // Decoration: the text beside it says what the screen is.
        .accessibilityHidden(true)
    }
}
