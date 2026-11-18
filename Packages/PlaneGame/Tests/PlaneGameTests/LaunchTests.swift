import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The plane's flight onto the field, and the scroll that starts with it.
struct LaunchTests {
    let envelopes = CGPoint(x: 200, y: 300)

    @Test func thePlaneHoldsWhereTheEnvelopesFoldUntilItSetsOff() {
        var world = PlaneGameWorld(field: phoneField, launch: .unfolding(at: envelopes), after: 0.5, seed: 1)
        world.run(for: 0.45, input: PlaneGameInput(slide: 3, isFiring: true))
        #expect(world.plane.position == envelopes)
        #expect(world.plane.trail.isEmpty)
        #expect(world.shots.isEmpty)
        #expect(world.speed == 0)
    }

    @Test func itFliesOntoTheMiddleOfTheLanesOnTheRowPointingUpAndThenFlies() {
        var world = PlaneGameWorld(field: phoneField, launch: .unfolding(at: envelopes), after: 0.5, seed: 1)
        world.run(for: 0.5 + FlightPath.duration / 2)
        guard case .launching = world.plane.status else {
            Issue.record("Still launching halfway along its path, got \(world.plane.status)")
            return
        }
        #expect(world.plane.position != envelopes)
        world.run(for: FlightPath.duration / 2 + frame)
        #expect(world.plane.status == .flying)
        #expect(world.plane.position == CGPoint(x: 200, y: phoneField.row))
        #expect(world.plane.heading == 0)
    }

    @Test func afterPlayAgainItComesStraightUpFromBelowTheBottomEdge() {
        var world = PlaneGameWorld(field: phoneField, launch: .fromBelow, after: 0, seed: 1)
        #expect(world.plane.position == CGPoint(x: 200, y: phoneField.size.height + PlaneGameRules.belowField))
        for _ in 0..<Int(FlightPath.duration / frame) {
            world.advance(by: frame, input: PlaneGameInput())
            #expect(world.plane.position.x == 200)
            #expect(abs(world.plane.heading) < 0.000_001)
        }
        world.run(for: 2 * frame)
        #expect(world.plane.position == phoneField.startingPlace)
    }

    @Test func withReduceMotionItIsSimplyInItsPlace() {
        var world = PlaneGameWorld(field: phoneField, launch: .inPlace, after: 0, seed: 1)
        #expect(world.plane.position == phoneField.startingPlace)
        world.run(for: FlightPath.duration / 2)
        #expect(world.plane.position == phoneField.startingPlace)
    }

    @Test func slidesDuringTheLaunchDontMoveThePlane() {
        var still = PlaneGameWorld(field: phoneField, launch: .unfolding(at: envelopes), after: 0.2, seed: 1)
        var slid = still
        for _ in 0..<40 {
            still.advance(by: frame, input: PlaneGameInput())
            slid.advance(by: frame, input: PlaneGameInput(slide: 9))
            #expect(slid.plane.position == still.plane.position)
        }
    }

    @Test func aResizeDuringTheLaunchHeadsForTheNewStartingPlace() {
        var world = PlaneGameWorld(field: phoneField, launch: .unfolding(at: envelopes), after: 0, seed: 1)
        world.run(for: 0.3)
        let landscape = windowFields[1]
        world.resize(to: landscape)
        world.run(for: FlightPath.duration)
        #expect(world.plane.status == .flying)
        #expect(world.plane.position == landscape.startingPlace)
    }

    @Test func theScrollEasesInFromTheMomentThePlaneSetsOff() {
        var world = PlaneGameWorld(field: phoneField, launch: .unfolding(at: envelopes), after: 0.5, seed: 1)
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

    @Test(arguments: windowFields)
    func theScrollKeepsToTheFieldsPace(field: PlaneGameField) {
        var world = PlaneGameWorld.flying(on: field)
        world.run(for: PlaneGameRules.hardeningTime)
        #expect(abs(world.speed - PlaneGameRules.topSpeed * field.pace) < 0.001)
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
