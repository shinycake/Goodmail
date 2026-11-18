import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The plane over time: its launch, steering, blinking and fall, its trail and its gun. Hits come from the collisions
/// in `PlaneGameWorld+Step.swift`, through `hitPlane()`.
extension PlaneGameWorld {
    /// Moves the plane on by `dt`, moving its status along with the clock.
    mutating func movePlane(by dt: TimeInterval, drag: CGSize) {
        switch plane.status {
        case .launching(let path, let elapsed):
            let now = elapsed + dt
            if now >= LoopPath.duration {
                plane.position = path.end
                plane.heading = path.heading(at: 1)
                plane.status = .flying
            } else {
                // Waiting, it stays at the start: `point(at:)` clamps.
                let progress = now / LoopPath.duration
                plane.position = path.point(at: progress)
                plane.heading = path.heading(at: progress)
                plane.status = .launching(path, elapsed: now)
            }
        case .flying:
            steer(by: drag, over: dt)
        case .shaken(let remaining):
            steer(by: drag, over: dt)
            plane.status = remaining > dt ? .shaken(remaining: remaining - dt) : .flying
        case .down(let elapsed):
            // Falling from rest so that, from anywhere on the field, it is past the bottom by `fallTime`.
            let drop = field.size.height + 2 * PlaneGameRules.planeRadius
            let gravity = 2 * drop / (PlaneGameRules.fallTime * PlaneGameRules.fallTime)
            plane.position.y += gravity * (elapsed + dt / 2) * dt
            plane.heading += PlaneGameRules.tumbleSpeed * dt
            plane.status = .down(elapsed: elapsed + dt)
        }
        sampleTrail(over: dt)
    }

    /// The plane hit something solid or a bad guy: a life lost, and then a blink or the fall.
    mutating func hitPlane() -> [PlaneGameEvent] {
        lives -= 1
        guard lives == 0 else {
            plane.status = .shaken(remaining: PlaneGameRules.shakenFor)
            return [.hit(livesLeft: lives)]
        }
        plane.status = .down(elapsed: 0)
        spawner.close()
        return [.hit(livesLeft: 0), .fell]
    }

    /// Fires while the finger is down and the plane is in play, never more often than `fireEvery`, however fast the
    /// finger taps. Steps are never longer than `fireEvery`, so one shot a step is enough.
    mutating func pullTrigger(_ isFiring: Bool, over dt: TimeInterval) {
        let wantsToFire = isFiring && plane.isInPlay
        switch trigger {
        case .ready where wantsToFire:
            fire()
            trigger = .cooling(sinceShot: 0)
        case .ready:
            break
        case .cooling(let since) where since + dt < PlaneGameRules.fireEvery:
            trigger = .cooling(sinceShot: since + dt)
        case .cooling(let since) where wantsToFire:
            fire()
            trigger = .cooling(sinceShot: since + dt - PlaneGameRules.fireEvery)
        case .cooling:
            trigger = .ready
        }
    }

    private mutating func fire() {
        shots.append(
            PlaneGameShot(
                id: takeID(), position: CGPoint(x: plane.position.x + PlaneGameRules.planeRadius, y: plane.position.y)))
    }

    /// Moves the plane by the finger's movement inside where it may fly, and tilts it with its climb.
    private mutating func steer(by drag: CGSize, over dt: TimeInterval) {
        let before = plane.position
        plane.position = field.keepingPlane(
            CGPoint(x: plane.position.x + drag.width, y: plane.position.y + drag.height))
        let climb = Double((plane.position.y - before.y) / dt)
        let tilt = min(max(climb * PlaneGameRules.tiltPerSpeed, -PlaneGameRules.maxTilt), PlaneGameRules.maxTilt)
        plane.heading += (tilt - plane.heading) * min(PlaneGameRules.tiltEasing * dt, 1)
    }

    /// Carries the trail back with the scroll and adds where the plane is now every `trailEvery`.
    private mutating func sampleTrail(over dt: TimeInterval) {
        guard !plane.isWaiting else { return }
        let scrolled = speed * dt
        for index in plane.trail.indices {
            plane.trail[index].x -= scrolled
        }
        sinceTrailSample += dt
        guard sinceTrailSample >= PlaneGameRules.trailEvery else { return }
        sinceTrailSample -= PlaneGameRules.trailEvery
        let previous = plane.trail.length
        plane.trail.insert(plane.position, at: 0)
        let newest = Array(plane.trail.prefix(2)).length
        // The usual trail is the last `trailLength` samples. Longer than that, as when a fast drag left a long
        // segment, the tail recedes as fast as the head moves on, so it shortens smoothly instead of dropping a
        // long segment at once.
        let usual = Array(plane.trail.prefix(PlaneGameRules.trailLength)).length
        let target = min(PlaneGameRules.trailReach, max(usual, previous - newest))
        plane.trail = plane.trail.cut(at: target)
    }
}

extension [CGPoint] {
    /// The length along the points, first to last.
    var length: CGFloat {
        zip(self, dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }.reduce(0, +)
    }

    /// The start of the points up to `reach` along them. The segment that crosses the reach ends at a point on it
    /// exactly there.
    func cut(at reach: CGFloat) -> [CGPoint] {
        var kept = Array(prefix(1))
        var length: CGFloat = 0
        for (from, to) in zip(self, dropFirst()) {
            let segment = hypot(to.x - from.x, to.y - from.y)
            guard length + segment > reach else {
                kept.append(to)
                length += segment
                continue
            }
            let share = (reach - length) / segment
            if share > 0 {
                kept.append(CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share))
            }
            break
        }
        return kept
    }
}

extension PlaneGamePlane {
    /// Waiting at its launch point to set off.
    var isWaiting: Bool {
        if case .launching(_, let elapsed) = status { elapsed < 0 } else { false }
    }

    /// Steering, firing and catching pickups.
    var isInPlay: Bool {
        switch status {
        case .flying, .shaken: true
        case .launching, .down: false
        }
    }
}
