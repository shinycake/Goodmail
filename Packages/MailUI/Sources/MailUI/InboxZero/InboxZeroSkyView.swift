import SwiftUI

/// The paper planes an empty Inbox sends off, drawn over the window's columns so they fly across the line between the
/// list and the empty pane beside it and leave by the window's edge. It takes no touches: the scene and the pane under
/// it take them. It draws only while the scene is awake and Reduce Motion is off, and fades with it as mail arrives.
struct InboxZeroSkyView: View {
    let sky: InboxZeroSky
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let reach = reduceMotion ? nil : sky.inbox?.reach
        ZStack {
            if let reach {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reach.wake == .asleep)) { timeline in
                    if let scene = sky.flights(at: timeline.date, rightToLeft: layoutDirection == .rightToLeft) {
                        PaperPlanes(scene: scene)
                    }
                }
                // Placed in the window's coordinates, which run from the left whatever the language.
                .environment(\.layoutDirection, .leftToRight)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.smooth(duration: 0.25), value: reach == nil)
    }
}
