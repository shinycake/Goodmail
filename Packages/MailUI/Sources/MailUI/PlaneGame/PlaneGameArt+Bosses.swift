import PlaneGame
import SwiftUI

/// How the bosses look: the bad guys' own frowning doodles, grown big, each with its own mark: Junk Mail a crown, the
/// Phisher a line and hook. The later bosses are in `PlaneGameArt+Roster.swift`.
nonisolated extension PlaneGameArt {
    /// A boss's line drawing, one unit across.
    static func boss(_ kind: PlaneGameBoss.Kind) -> DoodleArt {
        switch kind {
        case .junk: junkMail
        case .phisher: phisher
        case .storm: storm
        case .outOfOffice: outOfOffice
        case .mailingList: mailingList
        case .overload: overload
        }
    }

    /// What of a boss is filled, under its line: its outline alone, so the marks drawn over it, which are open
    /// lines, never fill as shapes when it flashes.
    static func body(_ kind: PlaneGameBoss.Kind) -> Path {
        switch kind {
        case .junk, .storm, .outOfOffice, .mailingList: envelopeBody
        case .phisher: atBody
        case .overload: overload.line
        }
    }

    private static let envelopeBody = DoodleShape.envelope.art.line
    private static let atBody = DoodleShape.at.art.line

    /// How many points across a boss is drawn.
    static func size(of kind: PlaneGameBoss.Kind) -> CGFloat {
        switch kind {
        case .junk: 96
        case .phisher: 88
        case .storm, .outOfOffice: 92
        case .mailingList: 76
        case .overload: 120
        }
    }

    /// The frowning spam envelope wearing a three-point crown on its top edge.
    private static let junkMail: DoodleArt = {
        var art = PlaneGameArt.art(of: .spam)
        art.line.addLines([
            CGPoint(x: -0.2, y: -0.33), CGPoint(x: -0.23, y: -0.55), CGPoint(x: -0.1, y: -0.43),
            CGPoint(x: 0, y: -0.6), CGPoint(x: 0.1, y: -0.43), CGPoint(x: 0.23, y: -0.55), CGPoint(x: 0.2, y: -0.33),
        ])
        return art
    }()

    /// The frowning at sign with a line hanging from its bottom and a hook on the end.
    private static let phisher: DoodleArt = {
        var art = PlaneGameArt.art(of: .phish)
        art.line.move(to: CGPoint(x: 0.02, y: 0.44))
        art.line.addLine(to: CGPoint(x: 0.02, y: 0.62))
        art.line.addQuadCurve(to: CGPoint(x: -0.1, y: 0.62), control: CGPoint(x: 0.02, y: 0.74))
        art.line.addLine(to: CGPoint(x: -0.06, y: 0.57))
        return art
    }()
}
