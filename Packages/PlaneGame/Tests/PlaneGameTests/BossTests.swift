import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// When a boss comes, how it is beaten and what it leaves.
struct BossTests {
    /// The game run up to just after the first boss is due, with nothing on the field.
    private func dueForABoss() -> PlaneGameWorld {
        var world = PlaneGameWorld.flying()
        while world.boss == nil, case .waves = world.encounter {
            world.advance(by: frame, input: PlaneGameInput())
        }
        return world
    }

    @Test func noBossComesBeforeFortySeconds() {
        var world = PlaneGameWorld.flying(arrivals: true)
        while world.elapsed < PlaneGameRules.firstBossAfter - frame {
            world.lives = PlaneGameRules.lives
            world.advance(by: frame, input: PlaneGameInput())
            #expect(world.boss == nil)
            guard case .waves = world.encounter else {
                Issue.record("The field began to clear at \(world.elapsed) s")
                return
            }
        }
        world.run(for: 2 * frame)
        guard case .clearing(1, _) = world.encounter else {
            Issue.record("No boss was on its way at \(world.elapsed) s")
            return
        }
    }

    @Test func arrivalsStopAndTheBossWaitsForTheFieldToEmpty() {
        var world = PlaneGameWorld.flying(arrivals: true)
        while case .waves = world.encounter {
            world.lives = PlaneGameRules.lives
            world.advance(by: frame, input: PlaneGameInput())
        }
        let lastBefore = world.nextID
        world.things.removeAll()
        world.add(.spam, at: CGPoint(x: 60, y: 600))
        var waited: TimeInterval = 0
        while world.boss == nil {
            #expect(!world.things.isEmpty)
            world.advance(by: frame, input: PlaneGameInput())
            waited += frame
        }
        #expect(waited > 1)
        #expect(waited < PlaneGameRules.clearingAtMost)
        world.run(for: 0.5)
        #expect(world.things.allSatisfy { $0.id < lastBefore })
    }

    @Test func theBossComesAfterFourSecondsAtMost() {
        var world = dueForABoss()
        world.add(.stamp, at: CGPoint(x: 60, y: -40))
        world.run(for: PlaneGameRules.clearingAtMost - frame)
        #expect(world.boss == nil)
        world.run(for: 2 * frame)
        #expect(world.boss != nil)
        #expect(world.things.map(\.kind) == [.stamp])
    }

    @Test func itCantBeHitWhileItSlidesIn() throws {
        var world = dueForABoss()
        world.run(for: frame)
        var boss = try #require(world.boss)
        #expect(boss.status == .arriving(elapsed: 0))
        #expect(boss.position.y < 0)
        while case .arriving = boss.status {
            world.shootBoss()
            world.advance(by: frame, input: PlaneGameInput())
            boss = try #require(world.boss)
            if case .arriving = boss.status {
                #expect(boss.hitsLeft == boss.hits)
                #expect(!world.bursts.contains { $0.kind == .struck })
            }
        }
        #expect(boss.position.y == phoneField.ceiling + boss.radius)
    }

    @Test func eachHitShortensItAndTheLastStartsItsFall() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss()
        world.shootBoss()
        #expect(world.advance(by: frame, input: PlaneGameInput()).isEmpty)
        #expect(world.boss?.hitsLeft == 19)
        #expect(world.shots.isEmpty)
        #expect(world.bursts.map(\.kind) == [.struck])

        world.changeBoss { $0.hitsLeft = 1 }
        world.add(.spam, at: CGPoint(x: 60, y: 400))
        world.add(.lure, at: CGPoint(x: 300, y: 400))
        world.add(.postmark, at: CGPoint(x: 200, y: 400))
        world.shootBoss()
        #expect(world.advance(by: frame, input: PlaneGameInput()) == [.bossDown(points: 250)])
        #expect(world.score == 250)
        let boss = try #require(world.boss)
        #expect(boss.status == .falling(elapsed: 0))
        // Everything it sent pops; an obstacle stays.
        #expect(world.things.map(\.kind) == [.postmark])
        // Shots pass a falling boss.
        world.shootBoss()
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.shots.count == 1)
    }

    @Test(arguments: [3, 2])
    func aBeatenBossLeavesAHeartIfALifeIsMissingAndAPowerUp(lives: Int) throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss()
        world.lives = lives
        world.changeBoss { $0.hitsLeft = 1 }
        world.shootBoss()
        world.advance(by: frame, input: PlaneGameInput())
        let spot = try #require(world.boss).position
        world.run(for: PlaneGameRules.bossFall + frame)
        #expect(world.boss == nil)
        let drops = world.things.sorted { $0.position.x < $1.position.x }
        #expect(drops.count == 2)
        #expect(drops.first?.kind == (lives == 3 ? .star : .heart))
        #expect(drops.last.map { $0.kind.isPowerUp } == true)
        #expect(drops.allSatisfy { abs($0.position.x - spot.x) <= PlaneGameRules.bossDropSpacing })
    }

    @Test func ordinaryPlayCarriesOnAfterTheBossAndTheNextIsThePhisherWithMoreHits() throws {
        var world = PlaneGameWorld.flying(arrivals: true)
        world.meetBoss()
        world.changeBoss { $0.hitsLeft = 1 }
        world.shootBoss()
        world.advance(by: frame, input: PlaneGameInput())
        world.run(for: PlaneGameRules.bossFall + frame)
        let firstNew = world.nextID
        var fresh = false
        while world.boss == nil {
            world.lives = PlaneGameRules.lives
            world.advance(by: frame, input: PlaneGameInput())
            fresh = fresh || world.things.contains { $0.id >= firstNew && !$0.kind.isPowerUp }
        }
        #expect(fresh)
        let boss = try #require(world.boss)
        #expect(boss.kind == .phisher)
        #expect(boss.number == 2)
        #expect(boss.hits == 28)
    }

    @Test func theSecondBossComesFiftySecondsAfterTheFirstFell() {
        var world = PlaneGameWorld.flying()
        world.meetBoss()
        world.changeBoss { $0.hitsLeft = 1 }
        world.shootBoss()
        world.advance(by: frame, input: PlaneGameInput())
        world.run(for: PlaneGameRules.bossFall + frame)
        world.things.removeAll()
        world.run(for: PlaneGameRules.nextBossAfter - 0.1)
        guard case .waves = world.encounter else {
            Issue.record("The field began to clear early")
            return
        }
        // Over an empty field it comes on at once.
        world.run(for: 0.2)
        #expect(world.boss?.number == 2)
    }

    @Test(arguments: [
        (1, 20, PlaneGameBoss.Kind.junk), (2, 28, .phisher), (3, 36, .junk), (6, 60, .phisher), (9, 60, .junk),
    ])
    func bossesTakeTurnsWithEightMoreHitsEachUpToSixty(number: Int, hits: Int, kind: PlaneGameBoss.Kind) {
        let boss = PlaneGameBoss(number: number, on: phoneField)
        #expect(boss.hits == hits)
        #expect(boss.kind == kind)
        #expect(boss.points == 250 * number)
    }

    @Test(arguments: windowFields)
    func aResizeKeepsTheBossInsideTheLanesAndUnderTheCeiling(field: PlaneGameField) throws {
        for settled in [false, true] {
            var world = PlaneGameWorld.flying()
            world.meetBoss()
            if !settled { world.changeBoss { $0.status = .arriving(elapsed: 0.7) } }
            world.resize(to: field)
            for _ in 0..<300 {
                let boss = try #require(world.boss)
                #expect(field.lanes(inset: boss.radius).contains(boss.position.x))
                #expect(boss.position.y <= field.ceiling + boss.radius)
                world.advance(by: frame, input: PlaneGameInput(slide: 3))
            }
            let boss = try #require(world.boss)
            #expect(boss.position.y == field.ceiling + boss.radius)
        }
    }
}
