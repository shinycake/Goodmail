import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// How each kind moves: everything falls with the world, and bad guys and lures fall faster than it.
extension PlaneGameThing {
    /// Moves it on by `dt` with the world falling at `speed`, on `field`, keeping its x inside the lanes. A lure is
    /// the one thing that isn't kept in: it spreads until it is past a side edge.
    mutating func move(by dt: TimeInterval, speed: CGFloat, towardX planeX: CGFloat, on field: PlaneGameField) {
        age += dt
        position.y += (speed + kind.extraSpeed * field.pace) * dt
        switch kind {
        case .stamp:
            turn += PlaneGameRules.stampSpin * dt
        case .postmark:
            position.x = lane + PlaneGameRules.postmarkSway / 2 * swingPhase(PlaneGameRules.postmarkSwayPeriod)
        case .spam:
            position.x = lane + PlaneGameRules.spamWeave * swingPhase(PlaneGameRules.spamWeavePeriod)
        case .phish:
            let reach = PlaneGameRules.phishDrift * dt
            position.x += min(max(planeX - position.x, -reach), reach)
        case .star:
            turn += PlaneGameRules.starSpin * dt
        case .lure:
            position.x += drift * dt
        case .heart, .spread, .rapid, .shield, .sweep:
            break
        }
        if kind != .lure { position.x = field.lanes.clamping(position.x) }
    }

    private func swingPhase(_ period: TimeInterval) -> CGFloat {
        sin(2 * .pi * age / period)
    }
}

extension PlaneGameThing.Kind {
    /// How much faster than the world it falls, on a field whose pace is 1.
    var extraSpeed: CGFloat {
        switch self {
        case .spam: PlaneGameRules.spamExtraSpeed
        case .phish: PlaneGameRules.phishExtraSpeed
        case .lure: PlaneGameRules.lureExtraSpeed
        case .stamp, .postmark, .star, .heart, .spread, .rapid, .shield, .sweep: 0
        }
    }

    /// How far it swings to each side of the x it arrived at.
    var swing: CGFloat {
        switch self {
        case .postmark: PlaneGameRules.postmarkSway / 2
        case .spam: PlaneGameRules.spamWeave
        case .stamp, .phish, .star, .heart, .spread, .rapid, .shield, .sweep, .lure: 0
        }
    }
}
