import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Long games with random input, bosses and power-ups included: replayable, and never out of bounds.
struct SoakTests {
    /// Random slides, taps and frame lengths from `seed`, the same every time.
    private struct Player {
        var generator: SeededGenerator

        mutating func nextFrame() -> (dt: TimeInterval, input: PlaneGameInput) {
            let dt = TimeInterval.random(in: 0.004...0.05, using: &generator)
            let input = PlaneGameInput(
                slide: CGFloat.random(in: -25...25, using: &generator), isFiring: Bool.random(using: &generator))
            return (dt, input)
        }
    }

    /// Where the envelopes are when the plane unfolds from them, about where the Inbox draws them.
    private func envelopes(in field: PlaneGameField) -> CGPoint {
        CGPoint(x: field.size.width / 2, y: field.size.height * 0.35)
    }

    @Test(arguments: windowFields)
    func theSameSeedAndInputsGiveEqualWorlds(field: PlaneGameField) {
        let launch = PlaneGameLaunch.unfolding(at: envelopes(in: field))
        var first = PlaneGameWorld(field: field, launch: launch, after: 0.4, seed: 42)
        var second = first
        var different = PlaneGameWorld(field: field, launch: launch, after: 0.4, seed: 43)
        var player = Player(generator: SeededGenerator(seed: 9))
        var differed = false
        for _ in 0..<1200 {
            let (dt, input) = player.nextFrame()
            #expect(first.advance(by: dt, input: input) == second.advance(by: dt, input: input))
            different.advance(by: dt, input: input)
            differed = differed || first.things != different.things
        }
        #expect(first == second)
        #expect(differed)
    }

    @Test(arguments: windowFields)
    func fiveMinutesOfRandomInputStayInBounds(field: PlaneGameField) {
        var world = PlaneGameWorld(field: field, launch: .unfolding(at: envelopes(in: field)), after: 0.4, seed: 5)
        var player = Player(generator: SeededGenerator(seed: 11))
        var mostThings = 0
        var mostShots = 0
        var bossesMet: Set<Int> = []
        while world.elapsed < 300 {
            // A plane that never runs out of lives, so things keep arriving for the whole five minutes.
            world.lives = max(world.lives, 2)
            let (dt, input) = player.nextFrame()
            world.advance(by: dt, input: input)
            mostThings = max(mostThings, world.things.count)
            mostShots = max(mostShots, world.shots.count)
            let points =
                [world.plane.position] + world.plane.trail + world.things.map(\.position)
                + world.shots.map(\.position)
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), world.plane.heading.isFinite else {
                Issue.record("Not a number at \(world.elapsed) s")
                return
            }
            expectInBounds(world)
            if let boss = world.boss { bossesMet.insert(boss.number) }
        }
        #expect(world.distance > 280 * PlaneGameRules.cruisingSpeed * field.pace)
        #expect(mostThings <= 60)
        #expect(mostShots <= 48)
        #expect(bossesMet.contains(1))
    }

    /// Through the roster twice, each boss beaten after it has fought for a while, in every window.
    @Test(arguments: windowFields)
    func aRunThroughTheRosterTwiceStaysInBounds(field: PlaneGameField) {
        var world = PlaneGameWorld(field: field, launch: .unfolding(at: envelopes(in: field)), after: 0.4, seed: 8)
        var player = Player(generator: SeededGenerator(seed: 12))
        var kindsMet: Set<PlaneGameBoss.Kind> = []
        var mostThings = 0
        var mostShots = 0
        while world.round <= 13, world.elapsed < 3600 {
            world.lives = max(world.lives, 2)
            let (dt, input) = player.nextFrame()
            world.advance(by: dt, input: input)
            mostThings = max(mostThings, world.things.count)
            mostShots = max(mostShots, world.shots.count)
            guard world.things.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite }) else {
                Issue.record("Not a number at \(world.elapsed) s")
                return
            }
            expectInBounds(world)
            if let boss = world.boss {
                kindsMet.insert(boss.kind)
                if case .fighting = boss.status, boss.fightTime > 8 { world.beatBoss() }
            }
        }
        #expect(world.round == 14)
        #expect(kindsMet.count == PlaneGameBoss.Kind.allCases.count)
        #expect(mostThings <= 60)
        #expect(mostShots <= 48)
    }

    /// The plane on its row inside the lanes, everything but hazards inside the lanes, and every body of a boss
    /// inside the lanes and no lower than where it hovers.
    private func expectInBounds(_ world: PlaneGameWorld) {
        let field = world.field
        if world.plane.isInPlay {
            #expect(world.plane.position.y == field.row)
            #expect(field.lanes(inset: PlaneGameRules.planeRadius).contains(world.plane.position.x))
        }
        #expect(world.things.allSatisfy { $0.kind.role == .hazard || field.lanes.contains($0.position.x) })
        if let boss = world.boss {
            #expect(boss.bodies.allSatisfy { field.lanes(inset: boss.radius).contains($0.x) })
            #expect(boss.bodies.allSatisfy { $0.y <= field.ceiling + boss.radius })
            #expect(boss.bodies.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
    }

    @Test(arguments: 1...12)
    func aFightReplaysExactly(number: Int) {
        var first = PlaneGameWorld.flying()
        first.meetBoss(number)
        var second = first
        var player = Player(generator: SeededGenerator(seed: UInt64(number)))
        for _ in 0..<600 {
            let (dt, input) = player.nextFrame()
            #expect(first.advance(by: dt, input: input) == second.advance(by: dt, input: input))
        }
        #expect(first == second)
    }

    @Test func aNonsenseStepChangesNothingAndAHugeOneIsCapped() {
        let world = PlaneGameWorld.flying()
        for dt in [0, -1, .nan, .infinity] as [TimeInterval] {
            var stepped = world
            #expect(stepped.advance(by: dt, input: PlaneGameInput(isFiring: true)).isEmpty)
            #expect(stepped == world)
        }
        var paused = world
        paused.advance(by: 1e300, input: PlaneGameInput())
        #expect(abs(paused.elapsed - world.elapsed - PlaneGameRules.longestAdvance) < 0.000_001)
        var slid = world
        slid.advance(by: frame, input: PlaneGameInput(slide: .nan))
        #expect(slid.plane.position == world.plane.position)
    }
}
