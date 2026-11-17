import SwiftUI
import UIKit

/// One of the app icon's three envelopes, from the back of the pile to the front.
enum EnvelopeLayer: String, CaseIterable {
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
struct EnvelopePile: View {
    let width: CGFloat
    /// How wide the pile is fanned: 1 as in the icon, 0 squared up.
    let fan: Double
    /// Called when a finger that dragged the pile lets go.
    var released: () -> Void = {}
    @State private var pull = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lean = EnvelopeLean(pull: pull)
        ZStack {
            ForEach(EnvelopeLayer.allCases, id: \.self) { envelope in
                EnvelopeLayerImage(envelope: envelope)
                    .rotationEffect(.degrees(envelope.angle * (fan - 1)), anchor: EnvelopeLayer.pivot)
                    // Its own modifier, so letting go springs it back while the fan above changes every frame.
                    .rotationEffect(.degrees(envelope.angle * lean.spread), anchor: EnvelopeLayer.pivot)
                    .offset(x: lean.shift.width * envelope.depth, y: lean.shift.height * envelope.depth)
            }
        }
        .frame(width: width, height: width * EnvelopeLayer.aspect)
        .rotation3DEffect(.degrees(lean.pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(lean.yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .gesture(
            EnvelopeDrag(
                moved: { translation in
                    if !reduceMotion { pull = translation }
                },
                released: {
                    withAnimation(.spring(duration: 0.7, bounce: 0.6)) { pull = .zero }
                    released()
                }))
    }
}

/// A drag on the envelopes that leaves the screen's own scrolling alone. A SwiftUI drag gesture would claim the
/// touch, so a pull that started on the envelopes would tip them over without scrolling or pulling to refresh. A
/// UIKit pan that recognizes alongside every other gesture lets both happen at once.
private struct EnvelopeDrag: UIGestureRecognizerRepresentable {
    let moved: (CGSize) -> Void
    let released: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Alongside { Alongside() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed:
            let translation = pan.translation(in: pan.view)
            moved(CGSize(width: translation.x, height: translation.y))
        case .ended, .cancelled, .failed:
            released()
        case .possible:
            break
        @unknown default:
            break
        }
    }

    /// Lets the pan run alongside the scroll view's pan and the scene's taps.
    final class Alongside: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

/// An envelope as Icon Composer renders it for the current appearance. The renders ship as plain PNGs among the
/// module's resources: an asset catalog needs Xcode's asset compiler, which the Linux iOS build doesn't have.
private struct EnvelopeLayerImage: View {
    let envelope: EnvelopeLayer
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

/// How the envelopes lean under a finger dragging them by `pull`.
nonisolated struct EnvelopeLean: Equatable, Sendable {
    /// How far they follow the finger: half the way at first and then less and less, as if held on elastic.
    let shift: CGSize

    /// The farthest they can be pulled from their place, each way.
    static let reach: CGFloat = 50

    init(pull: CGSize) {
        shift = CGSize(
            width: Self.reach * tanh(pull.width / (2 * Self.reach)),
            height: Self.reach * tanh(pull.height / (2 * Self.reach)))
    }

    /// How far they tip over as they are dragged up or down, in degrees about the horizontal.
    var pitch: Double { -shift.height / Self.reach * 22 }
    /// How far they tip over as they are dragged sideways, in degrees about the vertical.
    var yaw: Double { shift.width / Self.reach * 22 }
    /// The fan opens as they are pulled, by up to half as much again.
    var spread: Double { min(hypot(shift.width, shift.height) / Self.reach, 1) * 0.5 }
}
