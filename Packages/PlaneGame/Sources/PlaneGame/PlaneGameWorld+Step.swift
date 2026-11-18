import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// One short step of the world: the clock, the plane, what moves, what arrives, and what touches.
extension PlaneGameWorld {
    mutating func step(by dt: TimeInterval, input: PlaneGameInput) -> [PlaneGameEvent] {
        elapsed += dt
        let speed = speed
        distance += speed * dt
        movePlane(by: dt, drag: input.drag)
        pullTrigger(input.isFiring, over: dt)
        moveShots(by: dt)
        moveThings(by: dt, speed: speed)
        ageBursts(by: dt)
        for arrival in spawner.arrivals(
            at: elapsed, in: field, livesMissing: lives < PlaneGameRules.lives, using: &generator)
        {
            add(arrival.kind, at: arrival.position)
        }
        return collideShots() + collidePlane()
    }

    private mutating func moveShots(by dt: TimeInterval) {
        for index in shots.indices {
            shots[index].position.x += PlaneGameRules.shotSpeed * dt
        }
        shots.removeAll { $0.position.x > field.size.width }
    }

    private mutating func moveThings(by dt: TimeInterval, speed: CGFloat) {
        for index in things.indices {
            things[index].move(by: dt, speed: speed, towardHeight: plane.position.y, band: field.band)
        }
        things.removeAll { $0.position.x < -PlaneGameRules.leaveBeyond }
    }

    private mutating func ageBursts(by dt: TimeInterval) {
        for index in bursts.indices {
            bursts[index].age += dt
        }
        bursts.removeAll { $0.age >= PlaneGameBurst.lifetime }
    }

    /// Shots stop on the first obstacle or bad guy they touch and pass over pickups.
    private mutating func collideShots() -> [PlaneGameEvent] {
        var events: [PlaneGameEvent] = []
        var flying: [PlaneGameShot] = []
        for shot in shots {
            guard
                let index = things.firstIndex(where: {
                    $0.kind.role != .pickup && $0.touches(shot.position, within: PlaneGameRules.shotRadius)
                })
            else {
                flying.append(shot)
                continue
            }
            switch things[index].kind.role {
            case .badGuy(_, let points) where things[index].hitsLeft <= 1:
                let downed = things.remove(at: index)
                score += points
                burst(.pop(points: points), at: downed.position)
                events.append(.shotDown(points: points))
            case .badGuy:
                things[index].hitsLeft -= 1
                burst(.tick, at: shot.position)
            case .obstacle, .pickup:
                burst(.tick, at: shot.position)
            }
        }
        shots = flying
        return events
    }

    /// The plane catches pickups while it is in play, and loses a life to the first obstacle or bad guy it touches
    /// while it can be hit. A bad guy that hits it is destroyed; an obstacle stays.
    private mutating func collidePlane() -> [PlaneGameEvent] {
        guard plane.isInPlay else { return [] }
        var events: [PlaneGameEvent] = []
        for thing in things where thing.touches(plane.position, within: PlaneGameRules.planeRadius) {
            switch thing.kind.role {
            case .pickup:
                catchPickup(thing)
                events.append(.caught(thing.kind))
            case .badGuy where plane.status == .flying:
                things.removeAll { $0.id == thing.id }
                burst(.pop(points: 0), at: thing.position)
                events += hitPlane()
            case .obstacle where plane.status == .flying:
                events += hitPlane()
            case .badGuy, .obstacle:
                break
            }
        }
        return events
    }

    private mutating func catchPickup(_ pickup: PlaneGameThing) {
        things.removeAll { $0.id == pickup.id }
        burst(.caught, at: pickup.position)
        switch pickup.kind {
        case .star: score += PlaneGameRules.starPoints
        case .heart: lives = min(lives + 1, PlaneGameRules.lives)
        case .stamp, .postmark, .spam, .phish: break
        }
    }

    private mutating func burst(_ kind: PlaneGameBurst.Kind, at position: CGPoint) {
        bursts.append(PlaneGameBurst(id: takeID(), kind: kind, position: position, age: 0))
    }
}

extension PlaneGameThing {
    /// Whether a circle of `radius` at `point` overlaps it.
    func touches(_ point: CGPoint, within radius: CGFloat) -> Bool {
        let reach = kind.radius + radius
        let dx = position.x - point.x
        let dy = position.y - point.y
        return dx * dx + dy * dy <= reach * reach
    }
}
