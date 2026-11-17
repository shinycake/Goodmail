import SwiftUI

/// A line drawing in a square one unit across, centered on the origin.
nonisolated struct WelcomeDoodleArt: Sendable {
    /// Stroked as a solid line.
    var line = Path()
    /// Stroked as a row of dots: a stamp's perforation, the path a plane has flown.
    var dots = Path()
}

/// The things doodled around the welcome screen's envelopes.
nonisolated enum WelcomeDoodleShape: Sendable {
    case plane, stamp, postmark, at, heart, star, sparkle, squiggle, envelope, ring, cross

    /// The way the paper plane's nose points as drawn, in radians clockwise from pointing right.
    static let planeHeading = atan2(-0.42, 0.48)

    var art: WelcomeDoodleArt {
        var art = WelcomeDoodleArt()
        switch self {
        case .plane:
            let nose = CGPoint(x: 0.48, y: -0.42)
            let fold = CGPoint(x: -0.12, y: 0.12)
            art.line.addLines([nose, CGPoint(x: -0.48, y: -0.08), fold, CGPoint(x: 0.08, y: 0.46)])
            art.line.closeSubpath()
            art.line.move(to: fold)
            art.line.addLine(to: nose)
            art.dots.move(to: CGPoint(x: -0.42, y: 0.3))
            art.dots.addQuadCurve(to: CGPoint(x: -1.25, y: 0.2), control: CGPoint(x: -0.8, y: 0.72))
        case .stamp:
            let edge = CGRect(x: -0.38, y: -0.48, width: 0.76, height: 0.96)
            art.dots.addRoundedRect(in: edge, cornerSize: CGSize(width: 0.06, height: 0.06))
            art.line.addRoundedRect(in: edge.insetBy(dx: 0.13, dy: 0.13), cornerSize: CGSize(width: 0.04, height: 0.04))
            art.line.addPath(Self.heartOutline, transform: CGAffineTransform(scaleX: 0.34, y: 0.34))
        case .postmark:
            art.line.addEllipse(in: CGRect(x: -0.5, y: -0.25, width: 0.5, height: 0.5))
            art.line.addEllipse(in: CGRect(x: -0.37, y: -0.12, width: 0.24, height: 0.24))
            for y in [-0.17, 0, 0.17] {
                art.line.addPath(Self.wave(from: CGPoint(x: 0.08, y: y), length: 0.52, humps: 2, height: 0.16))
            }
        case .at:
            art.line.addEllipse(in: CGRect(x: -0.17, y: -0.17, width: 0.34, height: 0.34))
            // The stem runs down the ring's right side and hooks out into the outer stroke, which sweeps back
            // over the top and around to the bottom right.
            let sweep = stride(from: 12.0, through: -300, by: -12).map { Self.point(radius: 0.44, degrees: $0) }
            art.line.move(to: CGPoint(x: 0.17, y: -0.17))
            art.line.addLine(to: CGPoint(x: 0.17, y: 0.07))
            art.line.addCurve(
                to: sweep[0], control1: CGPoint(x: 0.17, y: 0.22), control2: CGPoint(x: 0.4, y: 0.28))
            art.line.addLines(sweep)
        case .heart:
            art.line = Self.heartOutline
        case .star:
            let points = (0..<10).map {
                Self.point(radius: $0.isMultiple(of: 2) ? 0.48 : 0.21, degrees: Double($0) * 36 - 90)
            }
            art.line.addLines(points)
            art.line.closeSubpath()
        case .sparkle:
            art.line.move(to: CGPoint(x: 0, y: -0.5))
            for tip in [0.0, 90, 180, 270] {
                art.line.addQuadCurve(
                    to: Self.point(radius: 0.5, degrees: tip), control: Self.point(radius: 0.13, degrees: tip - 45))
            }
            art.line.closeSubpath()
        case .squiggle:
            art.line = Self.wave(from: CGPoint(x: -0.5, y: 0), length: 1, humps: 4, height: 0.3)
        case .envelope:
            art.line.addRoundedRect(
                in: CGRect(x: -0.48, y: -0.33, width: 0.96, height: 0.66), cornerSize: CGSize(width: 0.09, height: 0.09)
            )
            art.line.addLines([CGPoint(x: -0.44, y: -0.27), CGPoint(x: 0, y: 0.08), CGPoint(x: 0.44, y: -0.27)])
        case .ring:
            art.line.addEllipse(in: CGRect(x: -0.5, y: -0.5, width: 1, height: 1))
        case .cross:
            art.line.move(to: CGPoint(x: -0.5, y: 0))
            art.line.addLine(to: CGPoint(x: 0.5, y: 0))
            art.line.move(to: CGPoint(x: 0, y: -0.5))
            art.line.addLine(to: CGPoint(x: 0, y: 0.5))
        }
        return art
    }

    private static let heartOutline: Path = {
        var path = Path()
        let tip = CGPoint(x: 0, y: 0.42)
        let dip = CGPoint(x: 0, y: -0.2)
        path.move(to: tip)
        for side in [-1.0, 1.0] {
            let shoulder = CGPoint(x: side * 0.46, y: -0.08)
            path.addCurve(
                to: shoulder, control1: CGPoint(x: side * 0.2, y: 0.26), control2: CGPoint(x: side * 0.46, y: 0.12))
            path.addCurve(
                to: dip, control1: CGPoint(x: side * 0.46, y: -0.46), control2: CGPoint(x: side * 0.08, y: -0.46))
            path.move(to: tip)
        }
        return path
    }()

    /// A wavy line running right from `start`, `humps` humps long, alternating above and below it.
    private static func wave(from start: CGPoint, length: CGFloat, humps: Int, height: CGFloat) -> Path {
        var path = Path()
        let step = length / CGFloat(humps)
        path.move(to: start)
        for hump in 0..<humps {
            let x = start.x + step * CGFloat(hump)
            path.addQuadCurve(
                to: CGPoint(x: x + step, y: start.y),
                control: CGPoint(x: x + step / 2, y: start.y + (hump.isMultiple(of: 2) ? -height : height)))
        }
        return path
    }

    /// The point `radius` from the origin, `degrees` clockwise from pointing right.
    private static func point(radius: CGFloat, degrees: Double) -> CGPoint {
        CGPoint(x: radius * cos(degrees * .pi / 180), y: radius * sin(degrees * .pi / 180))
    }
}
