import PlaneGame
import SwiftUI

/// The boss and the power-ups on the plane, drawn into the game's canvas.
extension PlaneGameCanvas {
    /// The boss, on paper, or washed pink for the instant after a shot strikes it.
    func drawBoss(in context: inout GraphicsContext, ink: GraphicsContext.Shading) {
        guard let boss = frame.boss, boss.opacity > 0 else { return }
        let art = PlaneGameArt.boss(boss.kind)
        let size = PlaneGameArt.size(of: boss.kind)
        let placed = CGAffineTransform.identity.translatedBy(boss.position).scaledBy(x: size, y: size)
        let body = boss.isFlashing ? DoodlePalette.pink.opacity(0.35) : Color(uiColor: .systemBackground)
        context.opacity = frame.play * boss.opacity
        context.fill(art.line.applying(placed), with: .color(body))
        context.stroke(art.line.applying(placed), with: ink, style: DoodleField.line)
        context.opacity = frame.play
    }

    /// A beaten boss's three bursts, each bigger than a bad guy's, and its points rising from it.
    func drawBossFalling(in context: inout GraphicsContext, ink: GraphicsContext.Shading) {
        guard let boss = frame.boss else { return }
        for burst in boss.bursts {
            context.opacity = frame.play * (1 - burst.progress)
            let placed = CGAffineTransform.identity.translatedBy(burst.position).scaledBy(x: 1.8, y: 1.8)
            context.stroke(
                PlaneGameArt.pop(progress: burst.progress, reduceMotion: frame.reduceMotion).applying(placed),
                with: ink, style: DoodleField.line)
        }
        if let points = boss.points, points.opacity > 0 {
            context.opacity = frame.play * points.opacity
            let label = context.resolve(
                Text(verbatim: points.value.formatted(.number.sign(strategy: .always())))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(DoodlePalette.purple))
            context.draw(label, at: points.position)
        }
        context.opacity = frame.play
    }

    /// Bubble Wrap as a dotted ring around the plane, and the weapon as an arc under it.
    func drawKit(on plane: PlaneGameSprite, in context: inout GraphicsContext, ink: GraphicsContext.Shading) {
        guard let kit = frame.kit else { return }
        let around = CGAffineTransform.identity.translatedBy(plane.position)
        if kit.isWrapped {
            context.stroke(PlaneGameArt.wrap.applying(around), with: ink, style: DoodleField.dots)
        }
        if let share = kit.arc {
            context.stroke(PlaneGameArt.weaponArc(share: share).applying(around), with: ink, style: DoodleField.line)
        }
    }
}
