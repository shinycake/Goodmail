import PlaneGame
import SwiftUI

/// How the game's things look: the doodles' own line art, with angry faces on the bad guys, and the shots and bursts.
nonisolated enum PlaneGameArt {
    /// A thing's line drawing, one unit across.
    static func art(of kind: PlaneGameThing.Kind) -> DoodleArt {
        switch kind {
        case .stamp: stamp
        case .postmark: postmark
        case .spam: spam
        case .phish: phish
        case .star: star
        case .heart: heart
        }
    }

    /// The doodle it is drawn from.
    static func shape(of kind: PlaneGameThing.Kind) -> DoodleShape {
        switch kind {
        case .stamp: .stamp
        case .postmark: .postmark
        case .spam: .envelope
        case .phish: .at
        case .star: .star
        case .heart: .heart
        }
    }

    /// How many points across it is drawn.
    static func size(of kind: PlaneGameThing.Kind) -> CGFloat {
        switch kind {
        case .stamp: 46
        case .postmark: 56
        case .spam: 38
        case .phish: 34
        case .star, .heart: 24
        }
    }

    /// Which of the icon's colors it is drawn in: blue is solid, pink is a bad guy, purple is yours.
    static func tint(of kind: PlaneGameThing.Kind) -> Int {
        switch kind.role {
        case .obstacle: blue
        case .badGuy: pink
        case .pickup: purple
        }
    }

    /// The indices of `DoodlePalette.all`.
    static let blue = 0
    static let purple = 1
    static let pink = 2

    /// A shot, in points, flying toward the trailing edge from the origin.
    static let shot: Path = {
        var path = Path()
        path.move(to: CGPoint(x: -5, y: 0))
        path.addLine(to: CGPoint(x: 5, y: 0))
        return path
    }()

    /// The tick a shot leaves on something solid, in points around the origin.
    static let tick: Path = {
        var path = Path()
        path.addLines([CGPoint(x: -3.5, y: 0), CGPoint(x: -1, y: 3), CGPoint(x: 4, y: -3.5)])
        return path
    }()

    /// A bad guy coming apart `progress` of the way through, in points around the origin: eight short lines flying
    /// out and shrinking, or, with Reduce Motion on, holding their place.
    static func pop(progress: Double, reduceMotion: Bool) -> Path {
        let t = CGFloat(reduceMotion ? 0.4 : PlaneGameEasing.easeOut(progress))
        let inner = 7 + 18 * t
        let length = reduceMotion ? 6 : 7 * (1 - t) + 1
        var path = Path()
        for spoke in 0..<8 {
            let angle = Double(spoke) * .pi / 4 + .pi / 8
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            path.move(to: CGPoint(x: direction.x * inner, y: direction.y * inner))
            path.addLine(to: CGPoint(x: direction.x * (inner + length), y: direction.y * (inner + length)))
        }
        return path
    }

    /// A pickup caught `progress` of the way through: a ring spreading out, in points around the origin.
    static func caught(progress: Double, reduceMotion: Bool) -> Path {
        let radius = 10 + 14 * CGFloat(reduceMotion ? 0.3 : PlaneGameEasing.easeOut(progress))
        return Path(ellipseIn: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius))
    }

    private static let stamp = DoodleShape.stamp.art
    private static let postmark = DoodleShape.postmark.art
    private static let star = DoodleShape.star.art
    private static let heart = DoodleShape.heart.art

    /// The envelope frowning, with dot eyes under slanted brows. Drawn below the flap, where the envelope is plain,
    /// and bold enough to read at 38 points.
    private static let spam: DoodleArt = {
        var art = shape(of: .spam).art
        art.line.addPath(brows(inner: CGPoint(x: 0.08, y: 0.15), outer: CGPoint(x: 0.30, y: 0.06)))
        for side in [-1.0, 1.0] {
            art.line.addEllipse(in: CGRect(x: side * 0.17 - 0.025, y: 0.205, width: 0.05, height: 0.05))
        }
        return art
    }()

    /// The at sign frowning: the same brows over its inner ring, which reads as an eye.
    private static let phish: DoodleArt = {
        var art = shape(of: .phish).art
        art.line.addPath(brows(inner: CGPoint(x: 0.05, y: -0.24), outer: CGPoint(x: 0.24, y: -0.34)))
        return art
    }()

    /// Two brows slanting down toward the middle, from `outer` to `inner` on the right and mirrored on the left.
    private static func brows(inner: CGPoint, outer: CGPoint) -> Path {
        var path = Path()
        for side in [-1.0, 1.0] {
            path.move(to: CGPoint(x: side * outer.x, y: outer.y))
            path.addLine(to: CGPoint(x: side * inner.x, y: inner.y))
        }
        return path
    }
}

/// A doodle's line art as a shape, for SwiftUI layout like the HUD's lives and its way out.
nonisolated struct DoodleOutline: Shape {
    let shape: DoodleShape

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        return shape.art.line.applying(
            CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: side, y: side))
    }
}
