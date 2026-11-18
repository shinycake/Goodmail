import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// How each boss moves and attacks, and how it changes at half its hits.
struct BossFightTests {
    /// What arrives over `seconds` from now: things the world didn't hold before.
    private func sent(by world: inout PlaneGameWorld, over seconds: TimeInterval) -> [PlaneGameThing] {
        let firstNew = world.nextID
        world.run(for: seconds)
        return world.things.filter { $0.id >= firstNew }
    }

    @Test func junkMailDropsOneSpamThenTwoSideBySideOnceItIsAngry() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(1)
        let calm = sent(by: &world, over: 2 * PlaneGameRules.junkDropEvery)
        #expect(calm.map(\.kind) == [.spam, .spam])
        #expect(calm[0].position.y > calm[1].position.y)

        world.changeBoss { $0.hitsLeft = $0.hits / 2 }
        world.things.removeAll()
        world.run(for: PlaneGameRules.junkDropEvery)
        let angry = sent(by: &world, over: PlaneGameRules.junkAngryDropEvery)
        #expect(angry.map(\.kind) == [.spam, .spam])
        #expect(angry[0].position.y == angry[1].position.y)
        #expect(angry[0].position.x != angry[1].position.x)
    }

    @Test func junkMailGlidesAcrossTheLanesAndBack() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(1)
        var xs: [CGFloat] = []
        for _ in 0..<Int(PlaneGameRules.junkGlidePeriod / frame) {
            world.advance(by: frame, input: PlaneGameInput())
            xs.append(try #require(world.boss).position.x)
        }
        let lanes = phoneField.lanes(inset: try #require(world.boss).radius)
        #expect(try #require(xs.min()) - lanes.lowerBound < 1)
        #expect(lanes.upperBound - (try #require(xs.max())) < 1)
        #expect(abs(xs[xs.count - 1] - phoneField.startingPlace.x) < 6)
    }

    @Test func junkMailGlidesNoFartherFromTheMiddleOfAWideWindowThanItsReach() throws {
        let wide = PlaneGameField(size: CGSize(width: 1024, height: 860), lanes: 12...1012, ceiling: 80, row: 720)
        var world = PlaneGameWorld.flying(on: wide)
        world.meetBoss(1)
        var farthest: CGFloat = 0
        for _ in 0..<Int(PlaneGameRules.junkGlidePeriod / frame) {
            world.advance(by: frame, input: PlaneGameInput())
            farthest = max(farthest, abs(try #require(world.boss).position.x - wide.startingPlace.x))
        }
        #expect(abs(farthest - PlaneGameRules.junkGlideReach) < 1)
    }

    @Test func aLureSpreadsOutThroughTheSideAndIsGone() {
        var world = PlaneGameWorld.flying()
        world.add(.lure, at: CGPoint(x: phoneField.lanes.upperBound - 5, y: 100), drift: 200)
        world.run(for: 0.2)
        #expect(world.things.first.map { $0.position.x > phoneField.lanes.upperBound } == true)
        world.run(for: 0.5)
        #expect(world.things.isEmpty)
    }

    @Test func thePhisherCastsAFanOfThreeLuresThenFiveOnceItIsAngry() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(2)
        let calm = sent(by: &world, over: PlaneGameRules.phisherCastEvery)
        #expect(calm.map(\.kind) == Array(repeating: .lure, count: 3))
        world.run(for: 0.3)
        let spread = world.things.map(\.position.x).sorted()
        #expect(spread[0] < spread[1] && spread[1] < spread[2])

        world.changeBoss { $0.hitsLeft = $0.hits / 2 }
        world.things.removeAll()
        let angry = sent(by: &world, over: PlaneGameRules.phisherAngryCastEvery)
        #expect(angry.map(\.kind) == Array(repeating: .lure, count: 5))
    }

    @Test func thePhisherCreepsToOneSideOfThePlaneAndStaysThere() throws {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 150))
        world.meetBoss(2)
        world.run(for: PlaneGameRules.phisherHold)
        let before = try #require(world.boss).position.x
        world.run(for: 0.5)
        let after = try #require(world.boss).position.x
        #expect(abs(after - before - PlaneGameRules.phisherCreep / 2) < 2)
        world.run(for: 6)
        #expect(abs(try #require(world.boss).position.x - (world.plane.position.x - PlaneGameRules.phisherOffset)) < 1)
    }

    @Test func thePhisherBacksAwayFromAPlaneThatWaitsUnderIt() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(2)
        world.run(for: 6)
        #expect(
            abs(abs(try #require(world.boss).position.x - world.plane.position.x) - PlaneGameRules.phisherOffset) < 1)
    }

    @Test func thePhisherHoldsStillJustAfterItCasts() throws {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 150))
        world.meetBoss(2)
        while !world.things.contains(where: { $0.kind == .lure }) {
            world.advance(by: frame, input: PlaneGameInput())
        }
        let cast = try #require(world.boss).position.x
        world.run(for: PlaneGameRules.phisherHold - 2 * frame)
        #expect(try #require(world.boss).position.x == cast)
        world.run(for: 0.2)
        #expect(try #require(world.boss).position.x != cast)
    }

    @Test func inLanesTooNarrowForEitherSideThePhisherSettlesAtTheFartherEnd() throws {
        let narrow = PlaneGameField(size: CGSize(width: 240, height: 860), lanes: 12...228, ceiling: 80, row: 720)
        // The plane in the middle, with no room for the Phisher 90 points to either side of it.
        var world = PlaneGameWorld.flying(on: narrow)
        world.meetBoss(2)
        world.run(for: 6)
        var xs: [CGFloat] = []
        for _ in 0..<60 {
            world.advance(by: frame, input: PlaneGameInput())
            xs.append(try #require(world.boss).position.x)
        }
        #expect(xs.allSatisfy { $0 == narrow.lanes(inset: 40).upperBound })
    }

    @Test func aShotFiredFromUnderTheCreepingPhisherStillCatchesIt() throws {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 150))
        world.meetBoss(2)
        // Past its hold after slipping in, so it is creeping toward its place beside the plane.
        world.run(for: PlaneGameRules.phisherHold)
        let hits = try #require(world.boss).hitsLeft
        world.advance(
            by: frame, input: PlaneGameInput(slide: try #require(world.boss).position.x - world.plane.position.x))
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        // The shot climbs for about a second, and the Phisher keeps creeping while it does.
        world.run(for: 1.2)
        #expect(try #require(world.boss).hitsLeft == hits - 1)
    }

    @Test func thePhisherCrossesOverThePlaneWhenAWallLeavesNoRoomOnItsSide() throws {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 100))
        world.meetBoss(2)
        let lanes = phoneField.lanes(inset: try #require(world.boss).radius)
        world.changeBoss { $0.position.x = lanes.upperBound }
        world.run(for: 8)
        #expect(abs(try #require(world.boss).position.x - (world.plane.position.x - PlaneGameRules.phisherOffset)) < 1)
    }

    @Test func luresCantBeShotAndCostALife() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.lure, by: 150)
        world.advance(by: frame, input: PlaneGameInput(isFiring: true))
        world.run(for: 0.1)
        #expect(world.things.map(\.kind) == [.lure])
        #expect(world.shots.count == 1)
        #expect(world.bursts.isEmpty)

        world.things.removeAll()
        world.addAhead(.lure)
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.hit(livesLeft: 2)])
        #expect(world.things.isEmpty)
    }

    @Test func onlyWhatTheBossSendsArrivesDuringTheFight() {
        var world = PlaneGameWorld.flying(arrivals: true)
        world.meetBoss(2)
        for _ in 0..<Int(10 / frame) {
            world.lives = PlaneGameRules.lives
            world.advance(by: frame, input: PlaneGameInput())
            #expect(world.things.allSatisfy { $0.kind == .lure })
        }
    }

    @Test func aBossStopsAttackingOnceThePlaneIsDown() {
        var world = PlaneGameWorld.flying()
        world.meetBoss(1)
        world.lives = 1
        world.addAhead(.stamp)
        world.advance(by: frame, input: PlaneGameInput())
        world.things.removeAll()
        world.run(for: 3)
        #expect(world.things.isEmpty)
    }

    @Test func whatABossSendsFallsAtTheFieldsPace() throws {
        var speeds: [CGFloat] = []
        for field in windowFields {
            var world = PlaneGameWorld.flying(on: field)
            world.meetBoss(2)
            world.run(for: PlaneGameRules.phisherCastEvery)
            // The middle lure of the fan falls straight down.
            let lure = try #require(world.things.first { $0.kind == .lure && $0.drift == 0 })
            world.advance(by: frame, input: PlaneGameInput())
            let later = try #require(world.things.first { $0.id == lure.id })
            // How much faster than the world it falls, on a field whose pace is 1.
            speeds.append((later.position.y - lure.position.y) / CGFloat(frame) / field.pace - world.speed / field.pace)
        }
        #expect(speeds.allSatisfy { abs($0 - PlaneGameRules.lureExtraSpeed) < 0.5 })
    }
}
