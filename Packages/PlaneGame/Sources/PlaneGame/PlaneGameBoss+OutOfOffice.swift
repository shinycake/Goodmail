import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Out of Office puts its sign up as the fight starts and after each attack. While it is up, it creeps over the plane
/// and no shot hurts it: one fired after the sign went up comes straight back as a reply. Once the sign is down, it
/// holds still and can be hit.
/// It attacks by sending its colleagues, phish that home on the plane.
extension PlaneGameBoss {
    /// Its out-of-office sign is up: shots at it come straight back.
    public var isShielded: Bool {
        guard kind == .outOfOffice, case .fighting(let sinceAttack, _) = status else { return false }
        return sinceAttack < PlaneGameRules.oooSignUpFor / tempo
    }

    /// What its sign does to a shot fired `firedAgo` seconds ago: sends it back if the shot was fired after the sign
    /// went up, or stops it, taking no hit, if it was already climbing when the sign went up. A plane that stops
    /// firing as the sign goes up never gets shots back.
    func bounces(shotFiredAgo firedAgo: TimeInterval) -> Bool {
        guard isShielded, case .fighting(let sinceAttack, _) = status else { return false }
        return firedAgo <= sinceAttack
    }

    mutating func outOfOfficeCreep(by dt: TimeInterval, towardX planeX: CGFloat, on field: PlaneGameField) {
        guard isShielded else { return }
        let over = field.lanes(inset: radius).clamping(planeX)
        head(toward: over, speed: PlaneGameRules.oooCreep * CGFloat(tempo), over: dt)
    }

    var outOfOfficeWait: TimeInterval {
        max(PlaneGameRules.oooEvery - PlaneGameRules.oooQuicker * Double(level), PlaneGameRules.oooQuickest)
    }

    func outOfOfficeColleagues(on field: PlaneGameField) -> [Sent] {
        row(of: .phish, count: 2 + (level + 1) / 2, spacing: PlaneGameRules.oooSpacing, on: field)
    }
}
