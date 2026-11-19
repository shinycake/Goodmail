import PlaneGame
import SwiftUI

/// The boss and the power-ups on the plane, drawn into the game's canvas.
extension PlaneGameCanvas {
    /// The boss, every body of it, on paper, or washed pink for the instant after a shot strikes it, with Out of
    /// Office's sign as a dotted ring and a later tier's anger marks. It is drawn into a copy of the context clipped
    /// to under the ceiling, so as it slides in it comes out from under the score rather than over it.
    func drawBoss(in context: GraphicsContext, ink: GraphicsContext.Shading) {
        guard let boss = frame.boss, boss.opacity > 0 else { return }
        let field = frame.world.field
        var layer = context
        layer.clip(to: Path(CGRect(x: 0, y: field.ceiling, width: field.size.width, height: field.size.height)))
        layer.opacity = frame.play * boss.opacity
        let art = PlaneGameArt.boss(boss.kind)
        let outline = PlaneGameArt.body(boss.kind)
        let size = PlaneGameArt.size(of: boss.kind)
        let body = boss.isFlashing ? DoodlePalette.pink.opacity(0.35) : Color(uiColor: .systemBackground)
        let anger = PlaneGameArt.anger(marks: boss.tier)
        for position in [boss.position] + boss.copies {
            let placed = CGAffineTransform.identity.translatedBy(position).scaledBy(x: size, y: size)
            layer.fill(outline.applying(placed), with: .color(body))
            layer.stroke(art.line.applying(placed), with: ink, style: DoodleField.line)
            layer.stroke(anger.applying(placed), with: ink, style: DoodleField.line)
            if boss.isShielded {
                layer.stroke(PlaneGameArt.shieldRing.applying(placed), with: ink, style: DoodleField.dots)
            }
        }
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
