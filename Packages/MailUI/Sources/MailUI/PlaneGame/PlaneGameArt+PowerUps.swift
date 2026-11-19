import PlaneGame
import SwiftUI

/// How the power-ups and the lures look, and what the power-ups put on the plane: each power-up a small glyph in a
/// dotted ring, so the four read as one family and never as a star.
nonisolated extension PlaneGameArt {
    /// A power-up's line drawing, one unit across: its glyph as the line and its ring as the dots.
    static func powerUp(_ kind: PlaneGameThing.Kind) -> DoodleArt {
        var art = DoodleArt()
        art.dots.addEllipse(in: CGRect(x: -0.5, y: -0.5, width: 1, height: 1))
        art.line = glyph(kind)
        return art
    }

    /// A lure, one unit tall: a hook on a short line, the barb turned up.
    static let lure: DoodleArt = {
        var art = DoodleArt()
        art.line.move(to: CGPoint(x: 0.08, y: -0.5))
        art.line.addLine(to: CGPoint(x: 0.08, y: 0.18))
        art.line.addQuadCurve(to: CGPoint(x: -0.3, y: 0.14), control: CGPoint(x: 0.06, y: 0.56))
        art.line.addLine(to: CGPoint(x: -0.14, y: 0.0))
        return art
    }()

    /// Bubble Wrap around the plane, in points around its middle.
    static let wrapRadius: CGFloat = 20
    static let wrap = Path(ellipseIn: CGRect(x: -20, y: -20, width: 40, height: 40))

    /// The weapon's arc under the plane, in points around its middle: centered on straight down, `share` of its
    /// longest.
    static func weaponArc(share: Double) -> Path {
        var path = Path()
        let reach = 80 * share
        path.addArc(
            center: .zero, radius: 17, startAngle: .degrees(90 - reach), endAngle: .degrees(90 + reach),
            clockwise: false)
        return path
    }

    /// Bubble Wrap bursting `progress` of the way through: the ring spreading out from the plane, in points around
    /// its middle.
    static func unwrapped(progress: Double, reduceMotion: Bool) -> Path {
        let radius = wrapRadius + 12 * CGFloat(reduceMotion ? 0.3 : PlaneGameEasing.easeOut(progress))
        return Path(ellipseIn: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius))
    }

    private static func glyph(_ kind: PlaneGameThing.Kind) -> Path {
        var path = Path()
        switch kind {
        case .spread:
            // Three shots fanning up, apart from each other as the shots are: joined at a point, they read as an
            // arrow pointing down.
            let foot = CGPoint(x: 0, y: 0.26)
            for degrees in [-32.0, 0, 32] {
                let angle = degrees * .pi / 180
                let direction = CGPoint(x: sin(angle), y: -cos(angle))
                path.move(to: CGPoint(x: foot.x + 0.16 * direction.x, y: foot.y + 0.16 * direction.y))
                path.addLine(to: CGPoint(x: foot.x + 0.44 * direction.x, y: foot.y + 0.44 * direction.y))
            }
        case .rapid:
            // Two chevrons pointing up.
            for top in [-0.2, 0.0] {
                path.addLines([
                    CGPoint(x: -0.18, y: top + 0.16), CGPoint(x: 0, y: top), CGPoint(x: 0.18, y: top + 0.16),
                ])
            }
        case .shield:
            path.addEllipse(in: CGRect(x: -0.2, y: -0.2, width: 0.4, height: 0.4))
        case .sweep:
            // The eight-spoke burst a bad guy comes apart in.
            for spoke in 0..<8 {
                let angle = Double(spoke) * .pi / 4 + .pi / 8
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                path.move(to: CGPoint(x: direction.x * 0.1, y: direction.y * 0.1))
                path.addLine(to: CGPoint(x: direction.x * 0.27, y: direction.y * 0.27))
            }
        case .stamp, .postmark, .spam, .phish, .star, .heart, .lure, .reply, .bulk:
            break
        }
        return path
    }
}
