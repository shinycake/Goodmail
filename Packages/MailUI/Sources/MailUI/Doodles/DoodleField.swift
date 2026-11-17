import SwiftUI

/// Mail doodles drawn in line around the envelopes, in the icon's colors: they drift slowly, and a touch pushes them
/// aside. One canvas draws them all.
struct DoodleField: View {
    let doodles: [Doodle]
    let scene: DoodleScene
    /// The doodles drawing themselves in, or `nil` once they are all there.
    var reveal: DoodleReveal? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let inks = inks.map { GraphicsContext.Shading.color($0) }
        Canvas { context, _ in
            context.translateBy(x: Self.bleed, y: Self.bleed)
            for (index, doodle) in doodles.enumerated() {
                let phase = Double(index) * 1.7
                let turn = (scene.rightToLeft ? -1 : 1) * (doodle.angle + scene.sway(phase: phase))
                let position = scene.position(anchor: doodle.anchor, phase: phase)
                let drawn = reveal?.progress(at: position) ?? 1
                guard drawn > 0 else { continue }
                // A doodle drawing itself in grows the last bit of the way to its size as the line is drawn.
                let size = doodle.size * (0.85 + 0.15 * drawn)
                let placed = CGAffineTransform.identity
                    .translatedBy(position)
                    .rotated(by: turn * .pi / 180)
                    // Only the plane has a direction to mirror: an at sign reads the same in Hebrew.
                    .scaledBy(x: size * (doodle.shape == .plane && scene.rightToLeft ? -1 : 1), y: size)
                let line = drawn < 1 ? doodle.art.line.trimmedPath(from: 0, to: drawn) : doodle.art.line
                context.opacity = min(drawn / 0.4, 1)
                context.stroke(line.applying(placed), with: inks[doodle.tint], style: Self.line)
                // Dots can't be drawn a little at a time, so they fade in once the line is mostly there.
                context.opacity = min(max((drawn - 0.6) / 0.4, 0), 1)
                context.stroke(doodle.art.dots.applying(placed), with: inks[doodle.tint], style: Self.dots)
            }
        }
        .padding(-Self.bleed)
    }

    /// The icon's colors washed most of the way into the background, so the doodles sit behind the envelopes and
    /// the title. Mixed, not see-through, so they look the same with Reduce Transparency on. A dark background
    /// swallows more of a color than a light one, so less of it goes in.
    private var inks: [Color] {
        DoodlePalette.all.map {
            $0.mix(with: Color(uiColor: .systemBackground), by: colorScheme == .dark ? 0.4 : 0.55)
        }
    }

    /// The canvases reach this far past the field, so a doodle at its edge, drifting or pushed, and a plane looping
    /// near it aren't cut off where the field ends.
    static let bleed: CGFloat = 40

    static let line = StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
    static let dots = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5])
}
