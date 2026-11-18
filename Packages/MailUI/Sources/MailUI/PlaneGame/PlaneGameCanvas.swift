import PlaneGame
import SwiftUI

/// One frame of the game in one canvas: the ring of doodles in washed ink behind, then what is in play, the bursts,
/// and the plane with its trail in front. The world is in the window's coordinates, which are the canvas's, and up is
/// up in every language, so nothing in play is mirrored.
struct PlaneGameCanvas: View {
    let frame: PlaneGameFrame
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let washed = DoodleField.inks(for: colorScheme).map { GraphicsContext.Shading.color($0) }
        let inks = DoodlePalette.all.map { GraphicsContext.Shading.color($0) }
        Canvas { context, _ in
            drawBackdrop(in: &context, inks: washed)
            context.opacity = frame.play
            drawThings(in: &context, inks: inks)
            drawShots(in: &context, ink: inks[PlaneGameArt.purple])
            drawBursts(in: &context, inks: inks)
            drawPlane(in: &context, ink: inks[PlaneGameArt.purple])
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawBackdrop(in context: inout GraphicsContext, inks: [GraphicsContext.Shading]) {
        for (doodle, drawn) in zip(Doodle.inboxZero, frame.backdrop) where drawn.opacity > 0 {
            context.opacity = drawn.opacity
            let pose = drawn.pose
            let placed = doodle.shape.placement(
                at: pose.position, angle: pose.angle, size: doodle.size, rightToLeft: frame.ringRightToLeft)
            context.stroke(doodle.art.line.applying(placed), with: inks[doodle.tint], style: DoodleField.line)
            context.stroke(doodle.art.dots.applying(placed), with: inks[doodle.tint], style: DoodleField.dots)
        }
    }

    private func drawThings(in context: inout GraphicsContext, inks: [GraphicsContext.Shading]) {
        let paper = GraphicsContext.Shading.color(Color(uiColor: .systemBackground))
        for thing in frame.world.things {
            let art = PlaneGameArt.art(of: thing.kind)
            let placed = PlaneGameArt.shape(of: thing.kind).placement(
                at: thing.position, angle: thing.turn, size: PlaneGameArt.size(of: thing.kind), rightToLeft: false)
            let ink = inks[PlaneGameArt.tint(of: thing.kind)]
            // Paper behind the line, so the backdrop doesn't show through what is in play.
            context.fill(art.line.applying(placed), with: paper)
            context.stroke(art.line.applying(placed), with: ink, style: DoodleField.line)
            context.stroke(art.dots.applying(placed), with: ink, style: DoodleField.dots)
        }
    }

    private func drawShots(in context: inout GraphicsContext, ink: GraphicsContext.Shading) {
        var shots = Path()
        for shot in frame.world.shots {
            shots.addPath(PlaneGameArt.shot, transform: CGAffineTransform.identity.translatedBy(shot.position))
        }
        context.stroke(shots, with: ink, style: Self.shot)
    }

    private func drawBursts(in context: inout GraphicsContext, inks: [GraphicsContext.Shading]) {
        let play = frame.play
        for burst in frame.world.bursts {
            let progress = min(max(burst.age / PlaneGameBurst.lifetime, 0), 1)
            let at = burst.position
            let moved = CGAffineTransform.identity.translatedBy(at)
            context.opacity = play * (1 - progress)
            switch burst.kind {
            case .pop(let points):
                let ink = inks[PlaneGameArt.pink]
                context.stroke(
                    PlaneGameArt.pop(progress: progress, reduceMotion: frame.reduceMotion).applying(moved), with: ink,
                    style: DoodleField.line)
                guard points > 0 else { continue }
                let rise = frame.reduceMotion ? 0 : 22 * CGFloat(PlaneGameEasing.easeOut(progress))
                let label = context.resolve(
                    Text(points, format: .number.sign(strategy: .always()))
                        .font(.callout.bold().monospacedDigit())
                        .foregroundStyle(DoodlePalette.purple))
                context.draw(label, at: CGPoint(x: at.x, y: at.y - 16 - rise))
            case .tick:
                context.stroke(
                    PlaneGameArt.tick.applying(moved), with: inks[PlaneGameArt.blue], style: DoodleField.line)
            case .caught:
                context.stroke(
                    PlaneGameArt.caught(progress: progress, reduceMotion: frame.reduceMotion).applying(moved),
                    with: inks[PlaneGameArt.purple], style: DoodleField.dots)
            }
        }
        context.opacity = play
    }

    private func drawPlane(in context: inout GraphicsContext, ink: GraphicsContext.Shading) {
        guard let plane = frame.plane, plane.opacity > 0, plane.width > 0 else { return }
        context.opacity = plane.opacity
        var trail = Path()
        trail.addLines(plane.trail)
        context.stroke(trail, with: ink, style: DoodleField.dots)
        // Drawn the way the scene's paper planes are, turned from where the art's nose points to the plane's heading,
        // and squeezed sideways as it opens from an upright line or folds back into one.
        let placed = CGAffineTransform.identity
            .translatedBy(plane.position)
            .scaledBy(x: plane.width, y: 1)
            .rotated(by: plane.heading - Self.artHeading)
            .scaledBy(x: Self.planeSize, y: Self.planeSize)
        context.fill(Self.planeArt.applying(placed), with: .color(Color(uiColor: .systemBackground)))
        context.stroke(Self.planeArt.applying(placed), with: ink, style: DoodleField.line)
    }

    /// The same size as the scene's paper planes, so the one the envelopes fold into matches them.
    static let planeSize: CGFloat = 30
    /// The way the art's nose points, in radians clockwise from pointing up.
    private static let artHeading = DoodleShape.planeHeading + .pi / 2
    private static let planeArt = DoodleShape.plane.art.line
    private static let shot = StrokeStyle(lineWidth: 2.5, lineCap: .round)
}
