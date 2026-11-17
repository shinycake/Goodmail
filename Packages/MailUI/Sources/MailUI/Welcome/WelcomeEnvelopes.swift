import SwiftUI
import UIKit

/// One of the app icon's three envelopes, from the back of the pile to the front.
enum WelcomeEnvelope: String, CaseIterable {
    case back = "Back"
    case mid = "Mid"
    case front = "Front"

    /// How far the icon turns it from upright to fan the pile, in degrees. Its render is already turned this far.
    var angle: Double {
        switch self {
        case .back: -15
        case .mid: -4
        case .front: 7
        }
    }

    /// How much of a drag it follows: the front one the most, the way the nearest thing moves the most.
    var depth: CGFloat {
        switch self {
        case .back: 0.3
        case .mid: 0.55
        case .front: 0.85
        }
    }

    /// The three renders share one canvas, this many times as tall as it is wide.
    static let aspect: CGFloat = 0.7
    /// The point the icon fans the envelopes around, just below that canvas.
    static let pivot = UnitPoint(x: 0.5375, y: 1.0747)
}

/// The app icon's three envelopes without its tile, each on its own layer so the pile can move: `fan` spreads it,
/// and a finger dragging it tips it over in depth and lets it spring back.
struct WelcomeEnvelopes: View {
    let width: CGFloat
    /// How wide the pile is fanned: 1 as in the icon, 0 squared up.
    let fan: Double
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.7, bounce: 0.6)))
    private var pull = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lean = WelcomeLean(pull: pull)
        ZStack {
            ForEach(WelcomeEnvelope.allCases, id: \.self) { envelope in
                WelcomeEnvelopeImage(envelope: envelope)
                    .rotationEffect(.degrees(envelope.angle * (fan - 1)), anchor: WelcomeEnvelope.pivot)
                    // Its own modifier, so letting go springs it back while the fan above changes every frame.
                    .rotationEffect(.degrees(envelope.angle * lean.spread), anchor: WelcomeEnvelope.pivot)
                    .offset(x: lean.shift.width * envelope.depth, y: lean.shift.height * envelope.depth)
            }
        }
        .frame(width: width, height: width * WelcomeEnvelope.aspect)
        .rotation3DEffect(.degrees(lean.pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(lean.yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        // Alongside the screen's scrolling, not instead of it: at the largest text sizes a drag here scrolls too.
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).updating($pull) { drag, pull, _ in pull = drag.translation },
            isEnabled: !reduceMotion
        )
    }
}

/// An envelope as Icon Composer renders it for the current appearance. The renders ship as plain PNGs among the
/// module's resources: an asset catalog needs Xcode's asset compiler, which the Linux iOS build doesn't have.
private struct WelcomeEnvelopeImage: View {
    let envelope: WelcomeEnvelope
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = UIImage(named: name, in: .module, with: nil) {
            Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
        }
    }

    private var name: String {
        switch colorScheme {
        case .dark: "WelcomeEnvelope\(envelope.rawValue)Dark"
        default: "WelcomeEnvelope\(envelope.rawValue)Light"
        }
    }
}
