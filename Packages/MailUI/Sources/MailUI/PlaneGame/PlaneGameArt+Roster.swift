import PlaneGame
import SwiftUI

/// How the bosses after the first two look, one unit across: the frowning spam envelope with a mark of its own, and
/// Inbox Overload drawn as an overflowing tray. Also Out of Office's sign and the marks of an angrier tier.
nonisolated extension PlaneGameArt {
    /// The envelope with a reply-all double arrow over its top edge.
    static let storm: DoodleArt = {
        var art = spam
        for tip in [-0.06, -0.24] {
            art.line.addLines([
                CGPoint(x: tip, y: -0.62), CGPoint(x: tip - 0.16, y: -0.5), CGPoint(x: tip, y: -0.38),
            ])
        }
        art.line.move(to: CGPoint(x: -0.22, y: -0.5))
        art.line.addLine(to: CGPoint(x: 0.18, y: -0.5))
        art.line.addQuadCurve(to: CGPoint(x: 0.34, y: -0.36), control: CGPoint(x: 0.34, y: -0.5))
        return art
    }()

    /// The envelope asleep, with a big Z and a small one over its top right corner.
    static let outOfOffice: DoodleArt = {
        var art = spam
        art.line.addLines([
            CGPoint(x: 0.1, y: -0.66), CGPoint(x: 0.3, y: -0.66), CGPoint(x: 0.1, y: -0.42), CGPoint(x: 0.3, y: -0.42),
        ])
        art.line.addLines([
            CGPoint(x: 0.36, y: -0.54), CGPoint(x: 0.48, y: -0.54), CGPoint(x: 0.36, y: -0.4),
            CGPoint(x: 0.48, y: -0.4),
        ])
        return art
    }()

    /// The envelope with a bulleted list of three standing on its top edge.
    static let mailingList: DoodleArt = {
        var art = spam
        for y in [-0.42, -0.52, -0.62] {
            art.line.addEllipse(in: CGRect(x: -0.3, y: y - 0.02, width: 0.04, height: 0.04))
            art.line.move(to: CGPoint(x: -0.2, y: y))
            art.line.addLine(to: CGPoint(x: 0.3, y: y))
        }
        return art
    }()

    /// An inbox tray with two letters sticking out of it, a badge on its corner and a frown on its front.
    static let overload: DoodleArt = {
        var art = DoodleArt()
        art.line.addLines([
            CGPoint(x: -0.5, y: -0.02), CGPoint(x: -0.42, y: 0.36), CGPoint(x: 0.42, y: 0.36),
            CGPoint(x: 0.5, y: -0.02),
            CGPoint(x: 0.2, y: -0.02), CGPoint(x: 0.13, y: 0.1), CGPoint(x: -0.13, y: 0.1), CGPoint(x: -0.2, y: -0.02),
        ])
        art.line.closeSubpath()
        art.line.addLines([
            CGPoint(x: -0.36, y: -0.02), CGPoint(x: -0.4, y: -0.34), CGPoint(x: -0.02, y: -0.4),
            CGPoint(x: 0, y: -0.02),
        ])
        art.line.addLines([CGPoint(x: -0.4, y: -0.34), CGPoint(x: -0.2, y: -0.18), CGPoint(x: -0.02, y: -0.4)])
        art.line.addLines([
            CGPoint(x: 0.02, y: -0.02), CGPoint(x: 0.06, y: -0.46), CGPoint(x: 0.36, y: -0.4),
            CGPoint(x: 0.34, y: -0.02),
        ])
        // The badge clear of the letter, so the two never overlap where the tray is filled.
        art.line.addEllipse(in: CGRect(x: 0.3, y: -0.72, width: 0.2, height: 0.2))
        art.line.addPath(brows(inner: CGPoint(x: 0.07, y: 0.2), outer: CGPoint(x: 0.26, y: 0.13)))
        for side in [-1.0, 1.0] {
            art.line.addEllipse(in: CGRect(x: side * 0.15 - 0.022, y: 0.25, width: 0.044, height: 0.044))
        }
        return art
    }()

    /// Out of Office's sign: a ring around it, in the art's units, stroked in dots.
    static let shieldRing = Path(ellipseIn: CGRect(x: -0.62, y: -0.62, width: 1.24, height: 1.24))

    /// Short strokes off a boss's upper corners, `marks` a side, for each time the roster has come round, at most
    /// three. They reach no farther out than the widest boss's art allows inside the lanes.
    static func anger(marks: Int) -> Path {
        angerMarks[max(min(marks, angerMarks.count - 1), 0)]
    }

    private static let angerMarks: [Path] = (0...3).map { marks in
        var path = Path()
        for degrees in [-40.0, -60, -80].prefix(marks) {
            let angle = degrees * .pi / 180
            for side in [-1.0, 1.0] {
                let direction = CGPoint(x: side * cos(angle), y: sin(angle))
                path.move(to: CGPoint(x: direction.x * 0.58, y: direction.y * 0.58))
                path.addLine(to: CGPoint(x: direction.x * 0.7, y: direction.y * 0.7))
            }
        }
        return path
    }
}
