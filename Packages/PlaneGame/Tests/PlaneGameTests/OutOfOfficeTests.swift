import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Out of Office sends shots back while its sign is up, and its colleagues at every attack.
struct OutOfOfficeTests {
    @Test func itComesInWithItsSignUpAndPutsItUpAfterEachAttack() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(4)
        #expect(try #require(world.boss).isShielded)
        world.run(for: PlaneGameRules.oooSignUpFor)
        #expect(try !#require(world.boss).isShielded)
        world.things.removeAll()
        world.runUntilBossAttacks(1)
        let phish = world.things.filter { $0.kind == .phish }.sorted { $0.position.x < $1.position.x }
        #expect(phish.count == 2)
        #expect(abs(phish[1].position.x - phish[0].position.x - PlaneGameRules.oooSpacing) < 0.001)
        #expect(try #require(world.boss).isShielded)
    }

    @Test func aShotFiredAfterItsSignWentUpComesStraightBackAsAReply() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(4)
        // The sign has been up for longer than the shot under it has been climbing.
        world.changeBoss { $0.status = .fighting(sinceAttack: 2, attacks: 1) }
        world.bursts.removeAll()
        world.shootBoss()
        let shot = try #require(world.shots.first)
        world.advance(by: frame, input: PlaneGameInput())
        let boss = try #require(world.boss)
        #expect(boss.hitsLeft == boss.hits)
        #expect(world.shots.isEmpty)
        let reply = try #require(world.things.first)
        #expect(reply.kind == .reply)
        #expect(abs(reply.position.x - shot.position.x) < 0.001)
        #expect(reply.drift == 0)
        #expect(world.bursts.map(\.kind) == [.tick])
        world.advance(by: frame, input: PlaneGameInput())
        let later = try #require(world.things.first)
        #expect(later.position.x == reply.position.x)
        #expect(later.position.y > reply.position.y)
    }

    @Test func aShotAlreadyClimbingWhenTheSignWentUpStopsOnItAndComesNoFurther() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(4)
        world.changeBoss { $0.status = .fighting(sinceAttack: 0.1, attacks: 1) }
        world.bursts.removeAll()
        world.shootBoss()
        world.advance(by: frame, input: PlaneGameInput())
        let boss = try #require(world.boss)
        #expect(boss.hitsLeft == boss.hits)
        #expect(world.shots.isEmpty)
        #expect(world.things.isEmpty)
        #expect(world.bursts.map(\.kind) == [.tick])
    }

    @Test func aPlaneThatStopsFiringAsTheSignGoesUpGetsNothingBack() {
        var world = PlaneGameWorld.flying()
        world.meetBoss(4)
        world.run(for: PlaneGameRules.oooSignUpFor)
        // Fire while the sign is down, then stop as it goes up with the first attack.
        world.run(
            for: PlaneGameRules.oooEvery - PlaneGameRules.oooSignUpFor - frame, input: PlaneGameInput(isFiring: true))
        world.run(for: 3)
        #expect(!world.things.contains { $0.kind == .reply })
        #expect(world.boss.map { $0.hitsLeft < $0.hits } == true)
    }

    @Test func aShotLandsOnceTheSignIsDown() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(4)
        world.run(for: PlaneGameRules.oooSignUpFor)
        world.shootBoss()
        world.advance(by: frame, input: PlaneGameInput())
        let boss = try #require(world.boss)
        #expect(boss.hitsLeft == boss.hits - 1)
        #expect(world.bursts.contains { $0.kind == .struck })
    }

    @Test func itFollowsThePlaneWhileItsSignIsUpAndHoldsStillOtherwise() throws {
        let wide = PlaneGameField(size: CGSize(width: 1024, height: 860), lanes: 12...1012, ceiling: 80, row: 720)
        var world = PlaneGameWorld.flying(on: wide)
        world.advance(by: frame, input: PlaneGameInput(slide: 450))
        world.meetBoss(4)
        let start = try #require(world.boss).position.x
        world.run(for: 1)
        let followed = try #require(world.boss).position.x - start
        #expect(abs(followed - PlaneGameRules.oooCreep) < 3)
        // Still on its way over the plane when the sign comes down, and then it stops.
        world.run(for: PlaneGameRules.oooSignUpFor - 1 + frame)
        let resting = try #require(world.boss).position.x
        #expect(resting < world.plane.position.x - 100)
        world.run(for: 1)
        #expect(try #require(world.boss).position.x == resting)
    }

    @Test func unsubscribeGoesThroughTheSign() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(4)
        world.addAhead(.sweep)
        world.advance(by: frame, input: PlaneGameInput())
        let boss = try #require(world.boss)
        #expect(boss.hitsLeft == boss.hits - PlaneGameRules.sweepBossHits)
    }

    @Test func itKeepsItsSignWhateverItBorrows() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(10)
        world.runUntilBossAttacks(3)
        let boss = try #require(world.boss)
        #expect(boss.attacker(at: 2) != .outOfOffice)
        #expect(boss.isShielded)
    }
}
