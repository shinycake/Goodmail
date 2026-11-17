import SwiftUI

/// The paper planes in the air, each trailing the dotted path it has flown. They fly in front of the envelopes.
struct PaperPlanes: View {
    let scene: DoodleScene

    var body: some View {
        Canvas { context, _ in
            for flight in scene.flights {
                context.opacity = flight.opacity
                let ink = GraphicsContext.Shading.color(DoodlePalette.all[flight.number % DoodlePalette.all.count])
                var trail = Path()
                trail.addLines(flight.trail)
                context.stroke(trail, with: ink, style: DoodleField.dots)
                // Mirrored when it flies left, so its keel stays underneath.
                let nose = scene.rightToLeft ? .pi - DoodleShape.planeHeading : DoodleShape.planeHeading
                let placed = CGAffineTransform.identity
                    .translatedBy(flight.position)
                    .rotated(by: flight.heading - nose)
                    .scaledBy(x: scene.rightToLeft ? -Self.size : Self.size, y: Self.size)
                // Paper, so it shows against an envelope of its own color.
                context.fill(Self.plane.applying(placed), with: .color(Color(uiColor: .systemBackground)))
                context.stroke(Self.plane.applying(placed), with: ink, style: DoodleField.line)
            }
        }
        .allowsHitTesting(false)
    }

    private static let plane = DoodleShape.plane.art.line
    private static let size: CGFloat = 30
}
