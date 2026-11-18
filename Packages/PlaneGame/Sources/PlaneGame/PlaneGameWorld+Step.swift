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
        movePlane(by: dt, slide: input.slide)
        weapon = weapon.aged(by: dt)
        pullTrigger(input.isFiring, over: dt)
        moveShots(by: dt)
        moveThings(by: dt, speed: speed)
        ageBursts(by: dt)
        stepEncounter(by: dt)
        return collideShots() + collidePlane()
    }

    /// Shots fly up, Reply All's side shots leaning out, and are gone past the top or a side edge.
    private mutating func moveShots(by dt: TimeInterval) {
        for index in shots.indices {
            shots[index].position.y -= PlaneGameRules.shotSpeed * dt
            shots[index].position.x += shots[index].drift * dt
        }
        shots.removeAll { $0.position.y < 0 || !(0...field.size.width).contains($0.position.x) }
    }

    private mutating func moveThings(by dt: TimeInterval, speed: CGFloat) {
        for index in things.indices {
            things[index].move(by: dt, speed: speed, towardX: plane.position.x, on: field)
        }
        let across = -PlaneGameRules.leaveBeyond...field.size.width + PlaneGameRules.leaveBeyond
        things.removeAll {
            $0.position.y > field.size.height + PlaneGameRules.leaveBeyond || !across.contains($0.position.x)
        }
    }

    private mutating func ageBursts(by dt: TimeInterval) {
        for index in bursts.indices {
            bursts[index].age += dt
        }
        bursts.removeAll { $0.age >= PlaneGameBurst.lifetime }
    }

    /// Shots stop on the first obstacle, bad guy or fighting boss they touch, and pass over pickups and through
    /// lures.
    private mutating func collideShots() -> [PlaneGameEvent] {
        var events: [PlaneGameEvent] = []
        var flying: [PlaneGameShot] = []
        for shot in shots {
            guard
                let index = things.firstIndex(where: {
                    $0.kind.role.stopsShots && $0.touches(shot.position, within: PlaneGameRules.shotRadius)
                })
            else {
                if let boss, boss.canBeHit, boss.touches(shot.position, within: PlaneGameRules.shotRadius) {
                    events += strikeBoss(1, at: shot.position)
                } else {
                    flying.append(shot)
                }
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
            case .obstacle, .pickup, .hazard:
                burst(.tick, at: shot.position)
            }
        }
        shots = flying
        return events
    }

    /// The plane catches pickups while it is in play, and loses a life to the first obstacle, bad guy or lure it
    /// touches while it can be hit. A bad guy or lure that hits it is destroyed; an obstacle stays.
    private mutating func collidePlane() -> [PlaneGameEvent] {
        guard plane.isInPlay else { return [] }
        var events: [PlaneGameEvent] = []
        for thing in things where thing.touches(plane.position, within: PlaneGameRules.planeRadius) {
            // Unsubscribe, caught earlier in this loop, may have popped it already.
            guard things.contains(where: { $0.id == thing.id }) else { continue }
            switch thing.kind.role {
            case .pickup:
                events += catchPickup(thing)
            case .badGuy where plane.status == .flying, .hazard where plane.status == .flying:
                things.removeAll { $0.id == thing.id }
                burst(.pop(points: 0), at: thing.position)
                events += hitPlane()
            case .obstacle where plane.status == .flying:
                events += hitPlane()
            case .badGuy, .obstacle, .hazard:
                break
            }
        }
        return events
    }

    mutating func burst(_ kind: PlaneGameBurst.Kind, at position: CGPoint) {
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
