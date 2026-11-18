import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What each pickup does once the plane catches it.
extension PlaneGameWorld {
    mutating func catchPickup(_ pickup: PlaneGameThing) -> [PlaneGameEvent] {
        things.removeAll { $0.id == pickup.id }
        burst(.caught, at: pickup.position)
        switch pickup.kind {
        case .star:
            score += PlaneGameRules.starPoints
        case .heart:
            lives = min(lives + 1, PlaneGameRules.lives)
        case .spread:
            weapon = .spread(remaining: PlaneGameRules.weaponTime)
        case .rapid:
            weapon = .rapid(remaining: PlaneGameRules.weaponTime)
        case .shield:
            // A second wrap is worth what a star is.
            if isShielded { score += PlaneGameRules.starPoints }
            isShielded = true
        case .sweep:
            popBadGuysAndHazards(scoring: true)
            if let boss {
                return [.powered(.sweep)] + strikeBoss(PlaneGameRules.sweepBossHits, at: boss.position)
            }
        case .stamp, .postmark, .spam, .phish, .lure:
            return []
        }
        return [pickup.kind.isPowerUp ? .powered(pickup.kind) : .caught(pickup.kind)]
    }

    /// Pops every bad guy and hazard on the field, for its points when `scoring`. Obstacles stay.
    mutating func popBadGuysAndHazards(scoring: Bool) {
        let popped = things.filter { $0.kind.role.pops }
        things.removeAll { $0.kind.role.pops }
        for thing in popped {
            let points = if scoring, case .badGuy(_, let points) = thing.kind.role { points } else { 0 }
            score += points
            burst(.pop(points: points), at: thing.position)
        }
    }
}
