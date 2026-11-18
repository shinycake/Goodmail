import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The dots behind the plane stay short however fast it moves.
struct TrailTests {
    @Test func aFastDragLeavesATrailNoLongerThanTheReach() {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(drag: CGSize(width: 0, height: 300)))
        for _ in 0..<60 {
            world.advance(by: frame, input: PlaneGameInput())
            #expect(world.plane.trail.length <= PlaneGameRules.trailReach + 0.0001)
        }
    }

    @Test func theFallLeavesATrailNoLongerThanTheReach() {
        var world = PlaneGameWorld.flying()
        world.lives = 1
        world.addAhead(.stamp)
        for _ in 0..<Int(PlaneGameRules.fallTime / frame) {
            world.advance(by: frame, input: PlaneGameInput())
            #expect(world.plane.trail.length <= PlaneGameRules.trailReach + 0.0001)
        }
        guard case .down = world.plane.status else {
            Issue.record("The plane should be falling")
            return
        }
    }

    @Test func theTailShortensSmoothlyAtTheReach() {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(drag: CGSize(width: 0, height: 300)))
        world.run(for: 0.1)
        let lengths = (0..<60).map { _ in
            world.advance(by: frame, input: PlaneGameInput())
            return world.plane.trail.length
        }
        // The long segment ages out of the usual trail in this second, and the tail draws in a little at a time.
        #expect(abs((lengths.first ?? 0) - PlaneGameRules.trailReach) < 0.0001)
        #expect(lengths.last ?? 0 < 60)
        #expect(zip(lengths, lengths.dropFirst()).allSatisfy { abs($0 - $1) < 10 })
    }

    @Test func levelFlightAtCruisingSpeedKeepsItsUsualTrail() {
        var world = PlaneGameWorld.flying()
        world.run(for: 1)
        let trail = world.plane.trail
        #expect(trail.count == PlaneGameRules.trailLength)
        let usual = PlaneGameRules.cruisingSpeed * PlaneGameRules.trailEvery * Double(PlaneGameRules.trailLength - 1)
        #expect(abs(trail.length - usual) < 2)
    }
}
