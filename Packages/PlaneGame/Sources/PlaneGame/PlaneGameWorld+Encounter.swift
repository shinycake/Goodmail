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
}

/// The encounter over time. `stepEncounter(by:)` is the one place it changes from one case to the next.
extension PlaneGameWorld {
    /// The boss on the field, for the screen to draw.
    public var boss: PlaneGameBoss? {
        if case .boss(let boss) = encounter { boss } else { nil }
    }

    /// Moves the encounter on by `dt` and puts on the field whatever it sends: ordinary arrivals, a boss's attacks,
    /// or what a beaten boss leaves.
    mutating func stepEncounter(by dt: TimeInterval) {
        switch encounter {
        case .waves(let played, let next):
            let wait = next == 1 ? PlaneGameRules.firstBossAfter : PlaneGameRules.nextBossAfter
            // A plane on its way down meets no boss.
            guard played + dt < wait || plane.isDown else {
                encounter = .clearing(number: next, elapsed: 0)
                return
            }
            encounter = .waves(played: played + dt, next: next)
            let openings = PlaneGameSpawner.Openings(
                livesMissing: lives < PlaneGameRules.lives, powerUpInPlay: things.contains { $0.kind.isPowerUp })
            for arrival in spawner.arrivals(at: elapsed, in: field, openings: openings, using: &generator) {
                add(arrival.kind, at: arrival.position)
            }
        case .clearing(let number, let elapsed):
            let now = elapsed + dt
            // Bad guys and obstacles are what a shot stops on.
            let isClear = !things.contains { $0.kind.role.stopsShots }
            encounter =
                isClear || now >= PlaneGameRules.clearingAtMost
                ? .boss(PlaneGameBoss(number: number, on: field)) : .clearing(number: number, elapsed: now)
        case .boss(var boss):
            let sent = boss.advance(by: dt, towardX: plane.position.x, on: field, attacking: !plane.isDown)
            for thing in sent {
                add(thing.kind, at: thing.position, drift: thing.drift)
            }
            guard boss.isGone else {
                encounter = .boss(boss)
                return
            }
            leaveDrops(of: boss)
            spawner.resume(at: elapsed, on: field)
            encounter = .waves(played: 0, next: boss.number + 1)
        }
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
