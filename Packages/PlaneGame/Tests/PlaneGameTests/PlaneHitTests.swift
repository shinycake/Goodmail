import Foundation
import Testing

@testable import PlaneGame

/// What touching things does to the plane.
struct PlaneHitTests {
    @Test(arguments: [PlaneGameThing.Kind.stamp, .postmark, .spam, .phish])
    func touchingAnObstacleOrBadGuyCostsALife(kind: PlaneGameThing.Kind) {
        var world = PlaneGameWorld.flying()
        world.addAhead(kind)
        let events = world.advance(by: frame, input: PlaneGameInput())
        #expect(events == [.hit(livesLeft: 2)])
        #expect(world.lives == 2)
        #expect(world.plane.status == .shaken(remaining: PlaneGameRules.shakenFor))
    }

    @Test func aBadGuyThatHitsThePlaneIsDestroyedWithoutAScore() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.spam)
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.things.isEmpty)
        #expect(world.bursts.map(\.kind) == [.pop(points: 0)])
        #expect(world.score == 0)
    }

    @Test func anObstacleThatHitsThePlaneStays() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.stamp)
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.things.map(\.kind) == [.stamp])
    }

    @Test func aShakenPlaneCantBeHitUntilItSettles() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.spam)
        world.advance(by: frame, input: PlaneGameInput())
        for _ in 0..<Int(PlaneGameRules.shakenFor / frame) - 1 {
            world.addAhead(.spam)
            #expect(world.advance(by: frame, input: PlaneGameInput()).isEmpty)
            world.things.removeAll()
        }
        #expect(world.lives == 2)
        world.run(for: 2 * frame)
        #expect(world.plane.status == .flying)
        world.addAhead(.spam)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.hit(livesLeft: 1)])
    }

    @Test func aShakenPlaneStillSteersFiresAndCatches() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.stamp)
        world.advance(by: frame, input: PlaneGameInput())
        let before = world.plane.position
        world.advance(by: frame, input: PlaneGameInput(slide: 30, isFiring: true))
        #expect(world.plane.position.x == before.x + 30)
        #expect(world.shots.count == 1)
        world.addAhead(.star)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.caught(.star)])
    }

    @Test func theThirdHitCostsTheGame() {
        var world = PlaneGameWorld.flying()
        world.lives = 1
        world.addAhead(.stamp)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.hit(livesLeft: 0), .fell])
        #expect(world.plane.status == .down(elapsed: 0))
        #expect(!world.isOver)
        let falling = world.run(for: PlaneGameRules.fallTime - 2 * frame, input: PlaneGameInput(isFiring: true))
        #expect(falling.isEmpty)
        #expect(world.shots.isEmpty)
        #expect(!world.isOver)
        world.run(for: 2 * frame)
        #expect(world.isOver)
        #expect(world.plane.position.y > phoneField.size.height)
    }

    @Test func nothingArrivesAfterThePlaneIsDownButTheWorldKeepsMoving() {
        var world = PlaneGameWorld.flying(arrivals: true)
        world.lives = 1
        world.addAhead(.stamp)
        world.advance(by: frame, input: PlaneGameInput())
        world.run(for: 4)
        #expect(world.things.isEmpty)
        let distance = world.distance
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.distance > distance)
    }

    @Test func aHeartGivesALifeBackUpToThree() {
        var world = PlaneGameWorld.flying()
        world.lives = 2
        world.addAhead(.heart)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.caught(.heart)])
        #expect(world.lives == 3)
        world.addAhead(.heart)
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.lives == 3)
        #expect(world.things.isEmpty)
    }

    @Test func aStarGivesFifty() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.star)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.caught(.star)])
        #expect(world.score == 50)
        #expect(world.bursts.map(\.kind) == [.caught])
    }

    @Test func thePlaneCantBeHitWhileItLaunches() {
        var world = PlaneGameWorld(field: phoneField, launch: .inPlace, after: 0.5, seed: 1)
        world.add(.stamp, at: phoneField.startingPlace)
        #expect(world.run(for: 0.2).isEmpty)
        #expect(world.lives == 3)
    }
}
