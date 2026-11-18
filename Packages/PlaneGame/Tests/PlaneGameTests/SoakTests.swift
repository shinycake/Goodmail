import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Long games with random input: replayable, and never out of bounds.
struct SoakTests {
    /// Random drags, taps and frame lengths from `seed`, the same every time.
    private struct Player {
        var generator: SeededGenerator

        mutating func nextFrame() -> (dt: TimeInterval, input: PlaneGameInput) {
            let dt = TimeInterval.random(in: 0.004...0.05, using: &generator)
            let input = PlaneGameInput(
                drag: CGSize(
                    width: CGFloat.random(in: -25...25, using: &generator),
                    height: CGFloat.random(in: -25...25, using: &generator)),
                isFiring: Bool.random(using: &generator))
            return (dt, input)
        }
    }

    private static let fields = [
        phoneField,
        PlaneGameField(size: CGSize(width: 1376, height: 1032), band: 90...990),
    ]

    @Test(arguments: fields)
    func theSameSeedAndInputsGiveEqualWorlds(field: PlaneGameField) {
        var first = PlaneGameWorld(field: field, launchingFrom: CGPoint(x: 200, y: 500), after: 0.4, seed: 42)
        var second = first
        var different = PlaneGameWorld(field: field, launchingFrom: CGPoint(x: 200, y: 500), after: 0.4, seed: 43)
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

    @Test(arguments: fields)
    func fiveMinutesOfRandomInputStayInBounds(field: PlaneGameField) {
        var world = PlaneGameWorld(field: field, launchingFrom: CGPoint(x: -40, y: 500), after: 0.4, seed: 5)
        var player = Player(generator: SeededGenerator(seed: 11))
        var mostThings = 0
        var mostShots = 0
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
            if world.plane.isInPlay {
                #expect(CGRect(origin: .zero, size: field.size).contains(world.plane.position))
            }
        }
        #expect(world.distance > 60_000)
        #expect(mostThings <= 60)
        #expect(mostShots <= 16)
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
        var dragged = world
        dragged.advance(by: frame, input: PlaneGameInput(drag: CGSize(width: CGFloat.nan, height: 4)))
        #expect(dragged.plane.position == world.plane.position)
    }
}
