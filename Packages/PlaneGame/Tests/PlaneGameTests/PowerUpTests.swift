import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What each power-up does, and when it stops.
struct PowerUpTests {
    @Test func replyAllFiresThreeShotsFanningUpForEightSeconds() throws {
        var world = PlaneGameWorld.flying()
        world.addAhead(.spread)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.powered(.spread)])
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        #expect(world.shots.count == 3)
        world.run(for: 0.1)
        let xs = world.shots.map(\.position.x).sorted()
        let middle = world.plane.position.x
        #expect(xs[1] == middle)
        #expect(abs((middle - xs[0]) - (xs[2] - middle)) < 0.0001)
        // Leaning 12 degrees from straight up.
        let shot = try #require(world.shots.first { $0.drift > 0 })
        let lean = atan2(Double(shot.drift), Double(PlaneGameRules.shotSpeed)) * 180 / .pi
        #expect(abs(lean - 12) < 0.0001)

        world.run(for: PlaneGameRules.weaponTime)
        #expect(world.weapon == .single)
        world.shots.removeAll()
        world.run(for: 0.1, input: PlaneGameInput(isFiring: true))
        #expect(world.shots.count == 1)
    }

    @Test func expressFiresTwiceAsFastForEightSeconds() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.rapid)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.powered(.rapid)])
        world.run(for: 0.5, input: PlaneGameInput(isFiring: true))
        #expect(world.shots.count == 5)

        world.run(for: PlaneGameRules.weaponTime)
        #expect(world.weapon == .single)
        world.shots.removeAll()
        world.run(for: 0.5, input: PlaneGameInput(isFiring: true))
        #expect(world.shots.count == 3)
    }

    @Test func aWeaponReplacesTheOtherWithAFreshEightSeconds() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.spread)
        world.advance(by: frame, input: PlaneGameInput())
        world.run(for: 3)
        world.addAhead(.rapid)
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.weapon == .rapid(remaining: PlaneGameRules.weaponTime))
        world.run(for: 6)
        #expect(world.weapon != .single)
    }

    @Test func bubbleWrapTakesTheNextHitAndThePlaneStillBlinks() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.shield)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.powered(.shield)])
        #expect(world.isShielded)

        world.addAhead(.spam)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.hit(livesLeft: 3)])
        #expect(world.lives == 3)
        #expect(!world.isShielded)
        #expect(world.things.isEmpty)
        #expect(world.plane.status == .shaken(remaining: PlaneGameRules.shakenFor))
        #expect(world.bursts.map(\.kind).contains(.unwrapped))

        world.run(for: PlaneGameRules.shakenFor + frame)
        world.addAhead(.stamp)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.hit(livesLeft: 2)])
    }

    @Test func aSecondBubbleWrapScoresLikeAStar() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.shield)
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.score == 0)
        world.addAhead(.shield)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.powered(.shield)])
        #expect(world.score == PlaneGameRules.starPoints)
        #expect(world.isShielded)
    }

    @Test func unsubscribePopsBadGuysAndLuresForTheirPointsAndLeavesObstacles() {
        var world = PlaneGameWorld.flying()
        world.add(.spam, at: CGPoint(x: 60, y: 200))
        world.add(.phish, at: CGPoint(x: 140, y: 260))
        world.add(.lure, at: CGPoint(x: 220, y: 300))
        world.add(.stamp, at: CGPoint(x: 320, y: 200))
        world.addAhead(.sweep)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.powered(.sweep)])
        #expect(world.things.map(\.kind) == [.stamp])
        #expect(world.score == 35)
        #expect(world.bursts.map(\.kind).filter { $0 != .caught }.count == 3)
    }

    @Test func unsubscribeTakesFiveHitsOffABoss() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss()
        world.addAhead(.sweep)
        world.advance(by: frame, input: PlaneGameInput())
        let boss = try #require(world.boss)
        #expect(boss.hitsLeft == boss.hits - PlaneGameRules.sweepBossHits)
    }

    @Test func unsubscribeCanBeatABoss() {
        var world = PlaneGameWorld.flying()
        world.meetBoss()
        world.changeBoss { $0.hitsLeft = 3 }
        world.addAhead(.sweep)
        #expect(
            world.advance(by: frame, input: PlaneGameInput()) == [.powered(.sweep), .bossDown(points: 250)])
    }
}

/// When power-ups arrive.
struct PowerUpArrivalTests {
    /// The times power-ups arrive over ten minutes, when each one stays in play for `staysFor` seconds.
    private func powerUpTimes(staysFor: TimeInterval, seed: UInt64) -> [(time: TimeInterval, kind: PlaneGameThing.Kind)]
    {
        var spawner = PlaneGameSpawner()
        var generator = SeededGenerator(seed: seed)
        var arrived: [(time: TimeInterval, kind: PlaneGameThing.Kind)] = []
        for time in stride(from: 0, through: 600, by: 1.0 / 20) {
            let inPlay = arrived.last.map { time - $0.time < staysFor } ?? false
            let openings = PlaneGameSpawner.Openings(livesMissing: false, powerUpInPlay: inPlay)
            for arrival in spawner.arrivals(at: time, in: phoneField, openings: openings, using: &generator)
            where arrival.kind.isPowerUp {
                arrived.append((time, arrival.kind))
            }
        }
        return arrived
    }

    @Test(arguments: 1...5 as ClosedRange<UInt64>)
    func theyComeFromFifteenSecondsAtLeastTwelveApartAndEachAsOftenAsTheOthers(seed: UInt64) throws {
        let arrived = powerUpTimes(staysFor: 0, seed: seed)
        let first = try #require(arrived.first)
        #expect(first.time >= PlaneGameRules.powerUpsFrom)
        for (one, next) in zip(arrived, arrived.dropFirst()) {
            #expect(next.time - one.time >= PlaneGameRules.powerUpGap)
        }
        #expect(Set(arrived.map(\.kind)) == Set(PlaneGameThing.Kind.powerUps))
    }

    @Test(arguments: 1...5 as ClosedRange<UInt64>)
    func neverTwoAreInPlayAtOnce(seed: UInt64) {
        let arrived = powerUpTimes(staysFor: 20, seed: seed)
        #expect(arrived.count > 5)
        for (one, next) in zip(arrived, arrived.dropFirst()) {
            #expect(next.time - one.time >= 20)
        }
    }

    @Test func onTheFieldAPowerUpBlocksTheNext() {
        var mostOnTheField = 0
        for seed in 1...5 as ClosedRange<UInt64> {
            var world = PlaneGameWorld.flying(seed: seed, arrivals: true)
            // Out of the way at the side, so the plane catches little.
            world.advance(by: frame, input: PlaneGameInput(slide: -1000))
            while world.elapsed < PlaneGameRules.firstBossAfter - 1 {
                world.lives = PlaneGameRules.lives
                world.advance(by: frame, input: PlaneGameInput())
                mostOnTheField = max(mostOnTheField, world.things.count { $0.kind.isPowerUp })
            }
        }
        #expect(mostOnTheField == 1)
    }
}
