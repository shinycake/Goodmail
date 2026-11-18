import SwiftUI

/// The empty Inbox: the app's envelopes in a ring of doodles, with "All Caught Up" under them. It sits behind the
/// list, comes on when the Inbox empties and goes when mail arrives.
struct InboxZeroView: View {
    let model: InboxZeroModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let showing = model.showing {
                InboxZeroScene(showing: showing, model: model)
                    .padding(model.insets)
                    .transition(InboxZeroTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // The whole of the list's background, which the game converts to the window from.
        .coordinateSpace(.named(InboxZeroStage.space))
        .animation(reduceMotion ? .linear(duration: 0.3) : .smooth(duration: 0.25), value: model.showing == nil)
    }
}

/// The scene draws its own entrance, so coming on it changes nothing here; leaving, it lifts away and fades. With
/// Reduce Motion on it fades both ways.
private struct InboxZeroTransition: Transition {
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        let fades = phase == .didDisappear || (reduceMotion && phase == .willAppear)
        let lifts = phase == .didDisappear && !reduceMotion
        content
            .opacity(fades ? 0 : 1)
            .scaleEffect(lifts ? 0.92 : 1)
            .offset(y: lifts ? -12 : 0)
    }
}
