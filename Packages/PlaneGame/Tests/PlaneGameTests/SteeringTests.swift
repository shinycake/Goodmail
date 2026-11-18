import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Dragging anywhere moves the plane by as much as the finger moves.
struct SteeringTests {
    @Test func aDragMovesThePlaneByTheSameAmount() {
        var world = PlaneGameWorld.flying()
        let before = world.plane.position
        world.advance(by: frame, input: PlaneGameInput(drag: CGSize(width: 12, height: -20)))
        #expect(world.plane.position == CGPoint(x: before.x + 12, y: before.y - 20))
    }

    @Test func aLongStepMovesItByTheWholeDragToo() {
        var world = PlaneGameWorld.flying()
        let before = world.plane.position
        world.advance(by: 0.05, input: PlaneGameInput(drag: CGSize(width: 30, height: 15)))
        #expect(abs(world.plane.position.x - (before.x + 30)) < 0.0001)
        #expect(abs(world.plane.position.y - (before.y + 15)) < 0.0001)
    }

    @Test func itKeepsToTheLeadingPartOfTheWidthAndToTheBand() {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(drag: CGSize(width: 1000, height: -1000)))
        #expect(world.plane.position == CGPoint(x: 400 * PlaneGameRules.planeReach, y: 80))
        world.advance(by: frame, input: PlaneGameInput(drag: CGSize(width: -1000, height: 2000)))
        #expect(world.plane.position == CGPoint(x: PlaneGameRules.planeRadius, y: 760))
    }

    @Test func itTiltsNoseUpClimbingAndNoseDownDiving() {
        var climbing = PlaneGameWorld.flying()
        var diving = climbing
        climbing.run(for: 0.2, input: PlaneGameInput(drag: CGSize(width: 0, height: -4)))
        diving.run(for: 0.2, input: PlaneGameInput(drag: CGSize(width: 0, height: 4)))
        #expect(climbing.plane.heading < -0.1)
        #expect(diving.plane.heading > 0.1)
        #expect(abs(climbing.plane.heading) <= PlaneGameRules.maxTilt)
    }

    @Test func itSettlesLevelWhenTheFingerIsStill() {
        var world = PlaneGameWorld.flying()
        world.run(for: 0.2, input: PlaneGameInput(drag: CGSize(width: 0, height: -4)))
        world.run(for: 1)
        #expect(abs(world.plane.heading) < 0.001)
    }

    @Test func itsTrailIsCarriedBackByTheScroll() {
        var world = PlaneGameWorld.flying()
        world.run(for: 1)
        let trail = world.plane.trail
        #expect(trail.count == PlaneGameRules.trailLength)
        #expect(trail.allSatisfy { $0.y == world.plane.position.y })
        #expect(zip(trail, trail.dropFirst()).allSatisfy { $0.x > $1.x })
        #expect(trail[0].x <= world.plane.position.x)
    }

    @Test func aResizeKeepsThePlaneInsideTheField() {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(drag: CGSize(width: 1000, height: 1000)))
        world.resize(to: PlaneGameField(size: CGSize(width: 300, height: 500), band: 60...460))
        #expect(world.plane.position == CGPoint(x: 300 * PlaneGameRules.planeReach, y: 460))
    }
}
