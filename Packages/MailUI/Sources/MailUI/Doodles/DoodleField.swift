import SwiftUI

/// Mail doodles drawn in line around the envelopes, in the icon's colors: they drift slowly, and a touch pushes them
/// aside. One canvas draws them all.
struct DoodleField: View {
    let doodles: [Doodle]
    let scene: DoodleScene
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let inks = inks.map { GraphicsContext.Shading.color($0) }
        Canvas { context, _ in
            for (index, doodle) in doodles.enumerated() {
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
        DoodlePalette.all.map {
            $0.mix(with: Color(uiColor: .systemBackground), by: colorScheme == .dark ? 0.4 : 0.55)
        }
    }

    static let line = StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
    static let dots = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5])
}
