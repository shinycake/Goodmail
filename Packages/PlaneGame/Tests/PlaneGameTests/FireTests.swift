import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The plane fires straight up by itself while a finger is down, and shots hit what is above it.
struct FireTests {
    @Test func itFiresOnceAsTheFingerComesDownAndThenEveryFireInterval() {
        var world = PlaneGameWorld.flying()
        world.run(for: 0.5, input: PlaneGameInput(isFiring: true))
        #expect(world.shots.count == 3)
        #expect(Set(world.shots.map(\.position.x)) == [world.plane.position.x])
    }

    @Test func tappingFastFiresNoFasterThanHolding() {
        var world = PlaneGameWorld.flying()
        for tap in 0..<30 {
            world.advance(by: frame, input: PlaneGameInput(isFiring: tap.isMultiple(of: 2)))
        }
        #expect(world.shots.count == 3)
    }

    @Test func itHoldsFireWithoutAFinger() {
        var world = PlaneGameWorld.flying()
        world.run(for: 1)
        #expect(world.shots.isEmpty)
    }

    @Test func shotsFlyUpAndAreGoneAboveTheTopEdge() throws {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        let fired = try #require(world.shots.first)
        #expect(fired.position.y < world.plane.position.y)
        world.advance(by: frame, input: PlaneGameInput())
        let later = try #require(world.shots.first)
        #expect(later.position.x == fired.position.x)
        #expect(abs(fired.position.y - later.position.y - PlaneGameRules.shotSpeed * frame) < 0.0001)
        world.run(for: phoneField.row / PlaneGameRules.shotSpeed + 0.05)
        #expect(world.shots.isEmpty)
    }

    @Test func spamDiesToOneShotForTen() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.spam, by: 160)
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        let events = world.run(for: 0.2)
        #expect(events == [.shotDown(points: 10)])
        #expect(world.score == 10)
        #expect(world.things.isEmpty)
        #expect(world.bursts.map(\.kind) == [.pop(points: 10)])
    }

    @Test func phishTakesTwoShotsForTwentyFive() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.phish, by: 200)
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        world.run(for: 0.3)
        #expect(world.things.map(\.hitsLeft) == [1])
        #expect(world.score == 0)
        #expect(world.bursts.map(\.kind) == [.tick])
        let events = world.run(for: 0.3, input: PlaneGameInput(isFiring: true))
        #expect(events == [.shotDown(points: 25)])
        #expect(world.score == 25)
        #expect(world.things.isEmpty)
    }

    @Test func aShotStopsOnAnObstacleAndLeavesATick() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.stamp, by: 160)
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        world.run(for: 0.3)
        #expect(world.shots.isEmpty)
        #expect(world.things.map(\.kind) == [.stamp])
        #expect(world.bursts.map(\.kind) == [.tick])
        #expect(world.score == 0)
    }

    @Test func shotsPassOverPickups() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.star, by: 200)
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        world.run(for: 0.2)
        #expect(world.things.map(\.kind) == [.star])
        #expect(world.bursts.isEmpty)
    }

    @Test func burstsFadeAfterTheirLifetime() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.spam, by: 160)
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        world.run(for: 0.2)
        #expect(world.bursts.count == 1)
        world.run(for: PlaneGameBurst.lifetime)
        #expect(world.bursts.isEmpty)
    }

    @Test(arguments: PlaneGameThing.Kind.allCases)
    func thingsThatPassTheBottomEdgeAreRemovedWithoutAScore(kind: PlaneGameThing.Kind) {
        var world = PlaneGameWorld.flying()
        world.add(kind, at: CGPoint(x: 330, y: 800))
        world.run(for: 1)
        #expect(world.things.isEmpty)
        #expect(world.score == 0)
        #expect(world.lives == PlaneGameRules.lives)
    }
}
