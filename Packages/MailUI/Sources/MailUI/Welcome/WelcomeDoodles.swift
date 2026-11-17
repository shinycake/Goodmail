import SwiftUI

/// The app icon's three envelope colors, for the welcome screen's decoration.
enum WelcomePalette {
    static let blue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let purple = Color(red: 0.69, green: 0.32, blue: 0.87)
    static let pink = Color(red: 1.0, green: 0.18, blue: 0.33)

    static let all = [blue, purple, pink]
}

/// Mail doodles drawn in line around the envelopes, in the icon's colors: they drift slowly, and a touch pushes them
/// aside. One canvas draws them all.
struct WelcomeDoodles: View {
    let scene: WelcomeScene
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let inks = inks.map { GraphicsContext.Shading.color($0) }
        Canvas { context, _ in
            for (index, doodle) in WelcomeDoodle.scatter.enumerated() {
                let phase = Double(index) * 1.7
                let turn = (scene.rightToLeft ? -1 : 1) * (doodle.angle + scene.sway(phase: phase))
                let placed = CGAffineTransform.identity
                    .translatedBy(scene.position(anchor: doodle.anchor, phase: phase))
                    .rotated(by: turn * .pi / 180)
                    // Only the plane has a direction to mirror: an at sign reads the same in Hebrew.
                    .scaledBy(x: doodle.size * (doodle.shape == .plane && scene.rightToLeft ? -1 : 1), y: doodle.size)
                context.stroke(doodle.art.line.applying(placed), with: inks[doodle.tint], style: Self.line)
                context.stroke(doodle.art.dots.applying(placed), with: inks[doodle.tint], style: Self.dots)
            }
        }
    }

    /// The icon's colors washed most of the way into the background, so the doodles sit behind the envelopes and
    /// the title. Mixed, not see-through, so they look the same with Reduce Transparency on. A dark background
    /// swallows more of a color than a light one, so less of it goes in.
    private var inks: [Color] {
        WelcomePalette.all.map {
            $0.mix(with: Color(uiColor: .systemBackground), by: colorScheme == .dark ? 0.4 : 0.55)
        }
    }

    static let line = StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
    static let dots = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5])
}

/// The paper planes in the air, each trailing the dotted path it has flown. They fly in front of the envelopes.
struct WelcomeFlights: View {
    let scene: WelcomeScene

    var body: some View {
        Canvas { context, _ in
            for flight in scene.flights {
                context.opacity = flight.opacity
                let ink = GraphicsContext.Shading.color(WelcomePalette.all[flight.number % WelcomePalette.all.count])
                var trail = Path()
                trail.addLines(flight.trail)
                context.stroke(trail, with: ink, style: WelcomeDoodles.dots)
                // Mirrored when it flies left, so its keel stays underneath.
                let nose = scene.rightToLeft ? .pi - WelcomeDoodleShape.planeHeading : WelcomeDoodleShape.planeHeading
                let placed = CGAffineTransform.identity
                    .translatedBy(flight.position)
                    .rotated(by: flight.heading - nose)
                    .scaledBy(x: scene.rightToLeft ? -Self.size : Self.size, y: Self.size)
                // Paper, so it shows against an envelope of its own color.
                context.fill(Self.plane.applying(placed), with: .color(Color(uiColor: .systemBackground)))
                context.stroke(Self.plane.applying(placed), with: ink, style: WelcomeDoodles.line)
            }
        }
        .allowsHitTesting(false)
    }

    private static let plane = WelcomeDoodleShape.plane.art.line
    private static let size: CGFloat = 30
}

extension CGAffineTransform {
    fileprivate func translatedBy(_ point: CGPoint) -> CGAffineTransform { translatedBy(x: point.x, y: point.y) }
}

/// One doodle and where it rests.
nonisolated struct WelcomeDoodle: Sendable {
    let shape: WelcomeDoodleShape
    /// Its place, as fractions of the stage's width and height.
    let anchor: CGPoint
    /// Decoration, not text, so a fixed size: the doodles keep their places at every text size.
    let size: CGFloat
    let angle: Double
    /// Which of the palette's colors it is drawn in.
    let tint: Int
    let art: WelcomeDoodleArt

    init(_ shape: WelcomeDoodleShape, x: CGFloat, y: CGFloat, size: CGFloat, angle: Double, tint: Int) {
        self.shape = shape
        anchor = CGPoint(x: x, y: y)
        self.size = size
        self.angle = angle
        self.tint = tint
        art = shape.art
    }

    /// A ring around the envelopes: along the top and bottom of the stage and down its sides, clear of the middle.
    static let scatter: [WelcomeDoodle] = [
        .init(.envelope, x: 0.11, y: 0.10, size: 34, angle: -14, tint: 0),
        .init(.sparkle, x: 0.31, y: 0.06, size: 16, angle: 0, tint: 2),
        .init(.at, x: 0.50, y: 0.07, size: 26, angle: 10, tint: 1),
        .init(.star, x: 0.70, y: 0.05, size: 19, angle: 12, tint: 0),
        .init(.plane, x: 0.90, y: 0.11, size: 34, angle: 0, tint: 2),
        .init(.heart, x: 0.065, y: 0.37, size: 22, angle: -12, tint: 2),
        .init(.stamp, x: 0.93, y: 0.42, size: 34, angle: 10, tint: 1),
        .init(.squiggle, x: 0.07, y: 0.63, size: 30, angle: -24, tint: 1),
        .init(.ring, x: 0.95, y: 0.68, size: 10, angle: 0, tint: 0),
        .init(.postmark, x: 0.11, y: 0.90, size: 40, angle: -8, tint: 0),
        .init(.cross, x: 0.35, y: 0.95, size: 10, angle: 20, tint: 2),
        .init(.sparkle, x: 0.60, y: 0.95, size: 14, angle: 0, tint: 1),
        .init(.squiggle, x: 0.75, y: 0.91, size: 30, angle: 8, tint: 0),
        .init(.star, x: 0.91, y: 0.88, size: 22, angle: -10, tint: 2),
    ]
}
