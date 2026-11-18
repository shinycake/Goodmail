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

    @Test func thePhisherCreepsTowardThePlane() throws {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 150))
        world.meetBoss(2)
        let before = try #require(world.boss).position.x
        world.run(for: 1)
        let after = try #require(world.boss).position.x
        #expect(abs(after - before - PlaneGameRules.phisherCreep) < 2)
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
