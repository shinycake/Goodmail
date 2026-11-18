import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// How each kind moves: obstacles and pickups ride with the world, and bad guys come faster than it.
extension PlaneGameThing {
    /// Moves it on by `dt` with the world scrolling at `speed`, keeping its height inside `band`.
    mutating func move(
        by dt: TimeInterval, speed: CGFloat, towardHeight planeHeight: CGFloat, band: ClosedRange<CGFloat>
    ) {
        age += dt
        switch kind {
        case .stamp:
            position.x -= speed * dt
            turn += PlaneGameRules.stampSpin * dt
        case .postmark:
            position.x -= speed * dt
            position.y = lane + PlaneGameRules.postmarkBob / 2 * swingPhase(PlaneGameRules.postmarkBobPeriod)
        case .spam:
            position.x -= (speed + PlaneGameRules.spamExtraSpeed) * dt
            position.y = lane + PlaneGameRules.spamWeave * swingPhase(PlaneGameRules.spamWeavePeriod)
        case .phish:
            position.x -= (speed + PlaneGameRules.phishExtraSpeed) * dt
            let reach = PlaneGameRules.phishDrift * dt
            position.y += min(max(planeHeight - position.y, -reach), reach)
        case .star:
            position.x -= speed * dt
            turn += PlaneGameRules.starSpin * dt
        case .heart:
            position.x -= speed * dt
        }
        position.y = band.clamping(position.y)
    }

    private func swingPhase(_ period: TimeInterval) -> CGFloat {
        sin(2 * .pi * age / period)
    }
}

extension PlaneGameThing.Kind {
    /// How far it swings above and below the height it arrived at.
    var swing: CGFloat {
        switch self {
        case .postmark: PlaneGameRules.postmarkBob / 2
        case .spam: PlaneGameRules.spamWeave
        case .stamp, .phish, .star, .heart: 0
        }
    }
}
