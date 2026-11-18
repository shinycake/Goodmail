import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A drag anywhere slides the plane sideways by as much as the finger moves sideways. It keeps to its row.
struct SteeringTests {
    @Test func aSlideMovesThePlaneSidewaysByTheSameAmount() {
        var world = PlaneGameWorld.flying()
        let before = world.plane.position
        world.advance(by: frame, input: PlaneGameInput(slide: 12))
        #expect(world.plane.position == CGPoint(x: before.x + 12, y: phoneField.row))
        world.advance(by: frame, input: PlaneGameInput(slide: -40))
        #expect(world.plane.position == CGPoint(x: before.x - 28, y: phoneField.row))
    }

    @Test func aLongStepMovesItByTheWholeSlideToo() {
        var world = PlaneGameWorld.flying()
        let before = world.plane.position
        world.advance(by: 0.05, input: PlaneGameInput(slide: 30))
        #expect(abs(world.plane.position.x - (before.x + 30)) < 0.0001)
        #expect(world.plane.position.y == phoneField.row)
    }

    @Test func itKeepsInsideTheLanesByItsRadius() {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 1000))
        #expect(world.plane.position == CGPoint(x: 388 - PlaneGameRules.planeRadius, y: phoneField.row))
        world.advance(by: frame, input: PlaneGameInput(slide: -2000))
        #expect(world.plane.position == CGPoint(x: 12 + PlaneGameRules.planeRadius, y: phoneField.row))
    }

    @Test func inLandscapeItKeepsClearOfTheSideSafeAreas() {
        let landscape = windowFields[1]
        var world = PlaneGameWorld.flying(on: landscape)
        world.advance(by: frame, input: PlaneGameInput(slide: -1000))
        #expect(world.plane.position.x == 62 + 12 + PlaneGameRules.planeRadius)
        world.advance(by: frame, input: PlaneGameInput(slide: 2000))
        #expect(world.plane.position.x == 874 - 62 - 12 - PlaneGameRules.planeRadius)
    }

    @Test(arguments: [CGFloat(4), -4])
    func itBanksTowardTheSlide(slide: CGFloat) {
        var world = PlaneGameWorld.flying()
        world.run(for: 0.2, input: PlaneGameInput(slide: slide))
        #expect(slide > 0 ? world.plane.heading > 0.1 : world.plane.heading < -0.1)
        #expect(abs(world.plane.heading) <= PlaneGameRules.maxBank)
    }

    @Test func aFastSlideBanksNoFurtherThanTheMost() {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: -170))
        // 360 points a second, which would bank it well past the most, for 180 points across the lanes.
        world.run(for: 0.5, input: PlaneGameInput(slide: 6))
        #expect(abs(world.plane.heading - PlaneGameRules.maxBank) < 0.01)
    }

    @Test func itLevelsWhenTheFingerIsStill() {
        var world = PlaneGameWorld.flying()
        world.run(for: 0.2, input: PlaneGameInput(slide: 4))
        world.run(for: 1)
        #expect(abs(world.plane.heading) < 0.001)
    }

    @Test func itsTrailIsCarriedDownByTheScroll() {
        var world = PlaneGameWorld.flying()
        world.run(for: 1)
        let trail = world.plane.trail
        #expect(trail.count == PlaneGameRules.trailLength)
        #expect(trail.allSatisfy { $0.x == world.plane.position.x })
        #expect(zip(trail, trail.dropFirst()).allSatisfy { $0.y < $1.y })
        #expect(trail[0].y >= world.plane.position.y)
    }

    @Test(arguments: windowFields)
    func aResizePutsThePlaneOnTheNewRowInsideTheNewLanes(field: PlaneGameField) {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 1000))
        world.resize(to: field)
        #expect(world.plane.position.y == field.row)
        #expect(world.plane.position.x <= field.lanes.upperBound - PlaneGameRules.planeRadius)
        #expect(world.plane.position.x >= field.lanes.lowerBound + PlaneGameRules.planeRadius)
    }

    @Test func aResizeThatLeavesThePlaneInsideTheLanesKeepsItsX() {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: -60))
        world.resize(to: windowFields[1])
        #expect(world.plane.position == CGPoint(x: 140, y: windowFields[1].row))
    }
}
