import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// How each kind comes down, at the pace of the field it plays on.
struct MotionTests {
    /// A cruising world, with the plane well to the left so nothing placed on the right reaches it.
    private func cruising(on field: PlaneGameField = phoneField) -> PlaneGameWorld {
        var world = PlaneGameWorld.flying(on: field)
        world.run(for: PlaneGameRules.rampTime)
        world.advance(by: frame, input: PlaneGameInput(slide: -1000))
        return world
    }

    @Test(arguments: [PlaneGameThing.Kind.stamp, .postmark, .star, .heart])
    func obstaclesAndPickupsFallWithTheWorld(kind: PlaneGameThing.Kind) throws {
        var world = cruising()
        world.add(kind, at: CGPoint(x: 300, y: 100))
        let before = try #require(world.things.first).position.y
        world.advance(by: frame, input: PlaneGameInput())
        let fell = try #require(world.things.first).position.y - before
        #expect(abs(fell - world.speed * frame) < 0.01)
    }

    @Test(arguments: [
        (PlaneGameThing.Kind.spam, PlaneGameRules.spamExtraSpeed), (.phish, PlaneGameRules.phishExtraSpeed),
    ])
    func badGuysFallFasterThanTheWorld(kind: PlaneGameThing.Kind, extra: CGFloat) throws {
        var world = cruising()
        world.add(kind, at: CGPoint(x: 300, y: 100))
        let before = try #require(world.things.first).position.y
        world.advance(by: frame, input: PlaneGameInput())
        let fell = try #require(world.things.first).position.y - before
        #expect(abs(fell - (world.speed + extra) * frame) < 0.01)
    }

    @Test(arguments: [
        (PlaneGameThing.Kind.spam, PlaneGameRules.spamWeave), (.postmark, PlaneGameRules.postmarkSway / 2),
    ])
    func spamAndPostmarksSwingWithinTheirWeaveOfWhereTheyArrived(kind: PlaneGameThing.Kind, weave: CGFloat) {
        var world = cruising()
        world.add(kind, at: CGPoint(x: 300, y: -40))
        var xs: [CGFloat] = []
        for _ in 0..<Int(3 / frame) {
            world.advance(by: frame, input: PlaneGameInput())
            xs += world.things.map(\.position.x)
        }
        #expect(xs.allSatisfy { abs($0 - 300) <= weave + 0.0001 })
        #expect((xs.max() ?? 0) - (xs.min() ?? 0) > 1.8 * weave)
    }

    @Test func phishClosesOnThePlanesX() throws {
        var world = cruising()
        world.add(.phish, at: CGPoint(x: 300, y: -40))
        world.run(for: 1)
        let phish = try #require(world.things.first)
        #expect(abs(phish.position.x - (300 - PlaneGameRules.phishDrift)) < 0.5)
    }

    @Test func phishSettlesOnThePlanesXWithoutOvershooting() throws {
        var world = cruising()
        let planeX = world.plane.position.x
        world.add(.phish, at: CGPoint(x: planeX + 20, y: -40))
        world.run(for: 1)
        #expect(try #require(world.things.first).position.x == planeX)
    }

    /// Seconds a star takes to fall from the ceiling to the row of `field`, once the world cruises.
    private func fallTime(on field: PlaneGameField) throws -> TimeInterval {
        var world = cruising(on: field)
        world.add(.star, at: CGPoint(x: field.lanes.upperBound - 20, y: field.ceiling))
        let start = world.elapsed
        while try #require(world.things.first).position.y < field.row {
            world.advance(by: frame, input: PlaneGameInput())
        }
        return world.elapsed - start
    }

    @Test func somethingTakesAboutAsLongToComeDownInEveryWindow() throws {
        let times = try windowFields.map(fallTime(on:))
        let longest = try #require(times.max())
        let shortest = try #require(times.min())
        #expect(shortest / longest > 0.9)
    }

    @Test func thePaceIsTheTravelFromCeilingToRowOverSixHundredForty() {
        #expect(phoneField.pace == 1)
        #expect(
            PlaneGameField(size: CGSize(width: 300, height: 260), lanes: 12...288, ceiling: 64, row: 200).pace == 0.35)
        #expect(
            PlaneGameField(size: CGSize(width: 1024, height: 1366), lanes: 12...1012, ceiling: 88, row: 1226).pace
                == 1.3)
    }

    @Test func aResizeBringsEveryThingInsideTheNewLanes() {
        var world = cruising()
        world.add(.spam, at: CGPoint(x: 350, y: 200))
        world.add(.stamp, at: CGPoint(x: 380, y: 300))
        let narrow = PlaneGameField(size: CGSize(width: 320, height: 860), lanes: 12...308, ceiling: 80, row: 720)
        world.resize(to: narrow)
        #expect(world.things.allSatisfy { narrow.lanes.contains($0.position.x) })
        #expect(world.things.map(\.position.y) == [200, 300])
        world.run(for: 2)
        #expect(world.things.allSatisfy { narrow.lanes.contains($0.position.x) })
    }

    @Test func theFieldOfAWindowKeepsItsLanesClearOfTheSidesAndItsRowAboveTheThumb() {
        let portrait = windowFields[0]
        #expect(portrait.lanes == 12...390)
        #expect(portrait.ceiling == 126)
        #expect(portrait.row == 720)
        let landscape = windowFields[1]
        #expect(landscape.lanes == 74...800)
        #expect(landscape.ceiling == 64)
        #expect(landscape.row == 317)
        let tiny = PlaneGameField(
            size: CGSize(width: 10, height: 60), safeTop: 0, safeLeft: 0, safeBottom: 0, safeRight: 0)
        #expect(tiny.lanes == 12...12)
        #expect(tiny.row == tiny.ceiling)
    }
}
