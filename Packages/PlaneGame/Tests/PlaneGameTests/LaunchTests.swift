import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The plane's loop onto the field, and the scroll that starts with it.
struct LaunchTests {
    let launch = CGPoint(x: 180, y: 600)
    let start = CGPoint(x: 88, y: 360)

    @Test func thePlaneHoldsAtItsLaunchPointUntilItSetsOff() {
        var world = PlaneGameWorld(field: phoneField, launchingFrom: launch, after: 0.5, seed: 1)
        world.run(for: 0.45, input: PlaneGameInput(drag: CGSize(width: 3, height: 3), isFiring: true))
        #expect(world.plane.position == launch)
        #expect(world.plane.trail.isEmpty)
        #expect(world.shots.isEmpty)
        #expect(world.speed == 0)
    }

    @Test func itFliesItsLoopToTheStartingPlaceAndThenFlies() {
        var world = PlaneGameWorld(field: phoneField, launchingFrom: launch, after: 0.5, seed: 1)
        world.run(for: 0.5 + LoopPath.duration / 2)
        guard case .launching = world.plane.status else {
            Issue.record("Still launching halfway through the loop, got \(world.plane.status)")
            return
        }
        #expect(world.plane.position != launch)
        world.run(for: LoopPath.duration / 2 + frame)
        #expect(world.plane.status == .flying)
        #expect(world.plane.position == start)
    }

    @Test func dragsDuringTheLaunchDontMoveThePlane() {
        var still = PlaneGameWorld(field: phoneField, launchingFrom: launch, after: 0.2, seed: 1)
        var dragged = still
        for _ in 0..<40 {
            still.advance(by: frame, input: PlaneGameInput())
            dragged.advance(by: frame, input: PlaneGameInput(drag: CGSize(width: 9, height: -7)))
            #expect(dragged.plane.position == still.plane.position)
        }
    }

    @Test func theScrollEasesInFromTheMomentThePlaneSetsOff() {
        var world = PlaneGameWorld(field: phoneField, launchingFrom: launch, after: 0.5, seed: 1)
        world.run(for: 0.5)
        #expect(world.speed == 0)
        world.run(for: 0.3)
        #expect(world.speed > 0)
        #expect(world.speed < PlaneGameRules.cruisingSpeed)
    }

    @Test func itCruisesAfterTheRampAndReachesTopSpeedAtTwoMinutes() {
        var world = PlaneGameWorld.flying()
        world.run(for: PlaneGameRules.rampTime)
        let rising = (PlaneGameRules.topSpeed - PlaneGameRules.cruisingSpeed) / PlaneGameRules.hardeningTime
        #expect(abs(world.speed - (PlaneGameRules.cruisingSpeed + rising * world.elapsed)) < 0.001)
        world.run(for: PlaneGameRules.hardeningTime - world.elapsed + frame)
        #expect(world.speed == PlaneGameRules.topSpeed)
        world.run(for: 60)
        #expect(world.speed == PlaneGameRules.topSpeed)
    }

    @Test func distanceIsTheScrollAddedUp() {
        var world = PlaneGameWorld.flying()
        let before = world.distance
        let speed = world.speed
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.distance > before + speed * frame)
        #expect(world.distance <= before + world.speed * frame)
    }
}
