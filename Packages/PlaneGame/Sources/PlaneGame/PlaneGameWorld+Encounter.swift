import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What the world is sending at the plane.
enum Encounter: Equatable, Sendable {
    /// Ordinary arrivals, for `played` seconds since the game began or the last boss fell. Boss `next` comes on
    /// after enough of them.
    case waves(played: TimeInterval, next: Int)
    /// Arrivals have stopped and the field is emptying before boss `number` comes on.
    case clearing(number: Int, elapsed: TimeInterval)
    case boss(PlaneGameBoss)

    /// The round being played: the number of the boss that ends it.
    var round: Int {
        switch self {
        case .waves(_, let next): next
        case .clearing(let number, _): number
        case .boss(let boss): boss.number
        }
    }
}

/// The encounter over time. `stepEncounter(by:)` is the one place it changes from one case to the next.
extension PlaneGameWorld {
    /// The boss on the field, for the screen to draw.
    public var boss: PlaneGameBoss? {
        if case .boss(let boss) = encounter { boss } else { nil }
    }

    /// Moves the encounter on by `dt` and puts on the field whatever it sends: ordinary arrivals, a boss's attacks,
    /// or what a beaten boss leaves. Beating a boss starts the next round.
    mutating func stepEncounter(by dt: TimeInterval) {
        switch encounter {
        case .waves(let played, let next):
            // A plane on its way down meets no boss.
            guard played + dt < PlaneGameRules.wavesBefore(boss: next) || plane.isDown else {
                encounter = .clearing(number: next, elapsed: 0)
                return
            }
            encounter = .waves(played: played + dt, next: next)
            let openings = PlaneGameSpawner.Openings(
                livesMissing: lives < PlaneGameRules.lives, powerUpInPlay: things.contains { $0.kind.isPowerUp },
                round: next)
            for arrival in spawner.arrivals(at: elapsed, in: field, openings: openings, using: &generator) {
                send(arrival.kind, at: arrival.position)
            }
        case .clearing(let number, let elapsed):
            let now = elapsed + dt
            // Bad guys and obstacles are what a shot stops on.
            let isClear = !things.contains { $0.kind.role.stopsShots }
            encounter =
                isClear || now >= PlaneGameRules.clearingAtMost
                ? .boss(PlaneGameBoss(number: number, on: field)) : .clearing(number: number, elapsed: now)
        case .boss(var boss):
            let bodies = boss.bodies.count
            let sent = boss.advance(
                by: dt, towardX: plane.position.x, on: field, scroll: speed, attacking: !plane.isDown)
            for thing in sent {
                send(thing.kind, at: thing.position, drift: thing.drift)
            }
            // A Mailing List that clones itself re-forms: every body pops where it now is.
            if boss.bodies.count != bodies {
                for body in boss.bodies {
                    burst(.pop(points: 0), at: body)
                }
            }
            guard boss.isGone else {
                encounter = .boss(boss)
                return
            }
            leaveDrops(of: boss)
            spawner.resume(at: elapsed, on: field, round: boss.number + 1)
            encounter = .waves(played: 0, next: boss.number + 1)
        }
    }

    /// A shot reaches a fighting boss at `point`: it strikes it, or Out of Office's sign stops it, taking no hit and
    /// sending it straight back as a reply if it was fired after the sign went up.
    mutating func shotReachesBoss(at point: CGPoint) -> [PlaneGameEvent] {
        guard let boss, boss.isShielded else { return strikeBoss(1, at: point) }
        burst(.tick, at: point)
        let firedAgo = (field.row - PlaneGameRules.planeRadius - point.y) / PlaneGameRules.shotSpeed
        if boss.bounces(shotFiredAgo: TimeInterval(firedAgo)) { send(.reply, at: point) }
        return []
    }

    /// Takes `count` hits off a fighting boss, struck at `point`. The last one beats it: its points are scored and
    /// everything it sent pops.
    mutating func strikeBoss(_ count: Int, at point: CGPoint) -> [PlaneGameEvent] {
        guard case .boss(var boss) = encounter, boss.canBeHit else { return [] }
        burst(.struck, at: point)
        let beaten = boss.strike(count)
        encounter = .boss(boss)
        guard beaten else { return [] }
        score += boss.points
        popBadGuysAndHazards(scoring: false)
        return [.bossDown(points: boss.points)]
    }

    /// A heart if a life is missing, a star if not, and a power-up, side by side where the boss was.
    private mutating func leaveDrops(of boss: PlaneGameBoss) {
        let reward: PlaneGameThing.Kind = lives < PlaneGameRules.lives ? .heart : .star
        let powerUp = PlaneGameSpawner.randomPowerUp(using: &generator)
        let half = PlaneGameRules.bossDropSpacing / 2
        let middle = field.lanes(inset: half + PlaneGameThing.Kind.star.radius).clamping(boss.position.x)
        add(reward, at: CGPoint(x: field.lanes.clamping(middle - half), y: boss.position.y))
        add(powerUp, at: CGPoint(x: field.lanes.clamping(middle + half), y: boss.position.y))
    }
}
