import PlaneGame
import SwiftUI

/// How what the later bosses send looks: replies, and Bulk Mail.
nonisolated extension PlaneGameArt {
    /// A reply, one unit tall: an arrow pointing down at the plane, its tail hooked back like a reply arrow's.
    static let reply: DoodleArt = {
        var art = DoodleArt()
        art.line.move(to: CGPoint(x: 0, y: -0.5))
        art.line.addLine(to: CGPoint(x: 0, y: 0.42))
        art.line.addLines([CGPoint(x: -0.26, y: 0.16), CGPoint(x: 0, y: 0.46), CGPoint(x: 0.26, y: 0.16)])
        art.line.move(to: CGPoint(x: 0, y: -0.5))
        art.line.addQuadCurve(to: CGPoint(x: 0.3, y: -0.3), control: CGPoint(x: 0.3, y: -0.5))
        return art
    }()

    /// Bulk Mail: the frowning envelope with a second one's edge showing behind it.
    static let bulk: DoodleArt = {
        var art = spam
        art.line.addLines([
            CGPoint(x: -0.36, y: -0.33), CGPoint(x: -0.36, y: -0.46), CGPoint(x: 0.58, y: -0.46),
            CGPoint(x: 0.58, y: 0.2), CGPoint(x: 0.48, y: 0.2),
        ])
        return art
    }()
}
