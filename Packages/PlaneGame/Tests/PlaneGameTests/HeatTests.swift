import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Each round plays harder than the last, by less each time.
struct HeatTests {
    @Test func theFirstRoundPlaysAsItAlwaysDid() {
        let heat = PlaneGameHeat(round: 1)
        #expect(heat.scroll == 1)
        #expect(heat.arrivals == 1)
        #expect(heat.hurry == 1)
    }

    @Test func heatRisesEveryRoundAndNeverReachesItsMost() {
        let heats = (1...200).map { PlaneGameHeat(round: $0) }
        for (before, after) in zip(heats, heats.dropFirst()) {
            #expect(after.scroll > before.scroll)
            #expect(after.arrivals > before.arrivals)
            #expect(after.hurry > before.hurry)
        }
        let far = PlaneGameHeat(round: 10_000)
        #expect(far.scroll < 1 + PlaneGameRules.heatScroll)
        #expect(far.arrivals < 1 + PlaneGameRules.heatArrivals)
        #expect(far.hurry < 1 + PlaneGameRules.heatHurry)
        let seventh = PlaneGameHeat(round: 7)
        #expect(abs(seventh.scroll - 1.2) < 0.000_1)
        #expect(abs(seventh.arrivals - 1.3) < 0.000_1)
        #expect(abs(seventh.hurry - 1.4) < 0.000_1)
    }

    @Test func theScrollIsFasterInALaterRound() {
        var world = PlaneGameWorld.flying()
        world.run(for: PlaneGameRules.hardeningTime)
        #expect(abs(world.speed - PlaneGameRules.topSpeed) < 0.001)
        world.encounter = .waves(played: 0, next: 7)
        #expect(abs(world.speed - PlaneGameRules.topSpeed * 1.2) < 0.001)
    }

    @Test func arrivalsComeMoreOftenInALaterRound() {
        #expect(PlaneGameSpawner.interval(at: 0) == PlaneGameRules.firstInterval)
        let late = PlaneGameSpawner.interval(at: PlaneGameRules.hardeningTime, round: 7)
        #expect(abs(late - PlaneGameRules.lastInterval / 1.3) < 0.000_1)
    }

    @Test func badGuysHurryInALaterRoundAndHazardsAndPickupsDont() throws {
        var world = PlaneGameWorld.flying()
        world.encounter = .waves(played: 0, next: 7)
        for kind in [PlaneGameThing.Kind.spam, .lure, .star] {
            world.add(kind, at: CGPoint(x: 200, y: 200))
        }
        let before = world.things
        world.advance(by: frame, input: PlaneGameInput())
        let fallen = zip(before, world.things).map { ($1.position.y - $0.position.y) / CGFloat(frame) - world.speed }
        #expect(abs(fallen[0] - PlaneGameRules.spamExtraSpeed * 1.4) < 0.5)
        #expect(abs(fallen[1] - PlaneGameRules.lureExtraSpeed) < 0.5)
        #expect(abs(fallen[2]) < 0.5)
        world.things.removeAll()
        world.add(.phish, at: CGPoint(x: world.plane.position.x + 150, y: 100))
        world.run(for: 1)
        let closed = 150 - (try #require(world.things.first).position.x - world.plane.position.x)
        #expect(abs(closed - PlaneGameRules.phishDrift * 1.4) < 1)
    }

    @Test func aLaterRoundsArrivalsComeFasterAndBringItsFormations() {
        var early = PlaneGameWorld.flying(arrivals: true)
        var late = early
        late.encounter = .waves(played: 0, next: 9)
        var lateCount = 0
        var earlyCount = 0
        var vees = 0
        for _ in 0..<Int(30 / frame) {
            early.lives = PlaneGameRules.lives
            late.lives = PlaneGameRules.lives
            earlyCount += early.newThings(over: frame).count
            let arrived = late.newThings(over: frame)
            lateCount += arrived.count
            if arrived.count == 5 && arrived.allSatisfy({ $0.kind == .spam }) { vees += 1 }
        }
        #expect(lateCount > earlyCount)
        #expect(vees > 0)
    }

    @Test func ordinaryPlayAfterABossCarriesOnInTheNextRound() throws {
        var world = PlaneGameWorld.flying(arrivals: true)
        world.encounter = .waves(played: 0, next: 4)
        world.meetBoss(4)
        world.beatBoss()
        world.run(for: PlaneGameRules.bossFall + frame)
        let after = world.elapsed
        guard case .waiting(let due) = world.spawner.state else {
            Issue.record("Arrivals didn't carry on")
            return
        }
        let interval = PlaneGameSpawner.interval(at: after, round: 5) / Double(phoneField.breadth)
        #expect(abs(due - after - interval) < 2 * frame)
    }

    @Test func bossesComeSoonerInLaterRounds() {
        let waits = [1, 2, 3, 4, 5, 6, 7, 60].map { PlaneGameRules.wavesBefore(boss: $0) }
        #expect(waits == [40, 50, 45, 40, 35, 30, 30, 30])
    }

    @Test func theRoundIsTheNumberOfTheComingBoss() throws {
        var world = PlaneGameWorld.flying()
        #expect(world.round == 1)
        world.meetBoss(1)
        #expect(world.round == 1)
        world.beatBoss()
        world.run(for: PlaneGameRules.bossFall - 2 * frame)
        #expect(world.round == 1)
        world.run(for: 3 * frame)
        #expect(world.boss == nil)
        #expect(world.round == 2)
    }

    @Test func theFieldTakesNoMoreThanItHolds() {
        var world = PlaneGameWorld.flying()
        world.meetBoss(1)
        for _ in 0..<PlaneGameRules.fieldHolds {
            world.add(.stamp, at: CGPoint(x: 200, y: -2000))
        }
        world.send(.spam, at: CGPoint(x: 100, y: 100))
        #expect(world.things.count == PlaneGameRules.fieldHolds)
        #expect(world.newThings(over: 5).isEmpty)
        world.beatBoss()
        world.run(for: PlaneGameRules.bossFall + frame)
        #expect(world.things.count == PlaneGameRules.fieldHolds + 2)
    }
}
