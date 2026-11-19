import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Inbox Overload patrols at a steady pace and alternates: a wall of spam with a gap that moves along it, then
/// another boss's attack, each of the other five in turn.
extension PlaneGameBoss {
    /// A triangle wave across its reach, starting from the middle.
    func overloadGlide(on field: PlaneGameField) -> CGFloat {
        let turn = fightTime * tempo / PlaneGameRules.overloadPeriod
        let triangle = 4 * abs((turn + 0.25).truncatingRemainder(dividingBy: 1) - 0.5) - 1
        return sway(triangle, reach: PlaneGameRules.overloadReach, on: field)
    }

    var overloadWait: TimeInterval {
        max(
            PlaneGameRules.overloadEvery - PlaneGameRules.overloadQuicker * Double(level),
            PlaneGameRules.overloadQuickest)
    }

    /// Seven slots of spam centered under it with two neighbors left empty: on the left, then the middle, then the
    /// right, and round again. A slot outside the lanes is left out rather than piled onto its neighbor.
    func overloadWall(on field: PlaneGameField, attack: Int) -> [Sent] {
        let wall = attack / 2
        let gap = -3 + (2 * wall) % 6
        let lanes = field.lanes(inset: PlaneGameThing.Kind.spam.radius + PlaneGameThing.Kind.spam.swing)
        return (-3...3).compactMap { slot in
            let x = muzzle.x + CGFloat(slot) * PlaneGameRules.overloadSpacing
            guard slot != gap, slot != gap + 1, lanes.contains(x) else { return nil }
            return Sent(kind: .spam, position: CGPoint(x: x, y: muzzle.y), drift: 0)
        }
    }
}
