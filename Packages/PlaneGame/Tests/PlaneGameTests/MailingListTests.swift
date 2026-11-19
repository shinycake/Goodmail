import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The Mailing List clones itself as it loses hits.
struct MailingListTests {
    @Test(arguments: [(5, [1, 2, 3]), (11, [2, 3, 4]), (17, [3, 4, 4])])
    func itStartsAsOneAndClonesItselfAtEachThird(number: Int, bodies: [Int]) throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(number)
        var counts: [Int] = []
        for share in [1.0, 0.6, 0.3] {
            world.changeBoss { $0.hitsLeft = Int(Double($0.hits) * share) }
            world.advance(by: frame, input: PlaneGameInput())
            counts.append(try #require(world.boss).bodies.count)
        }
        #expect(counts == bodies)
    }

    @Test func aShotAtAnyBodyTakesAHitOffTheOnePool() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(5)
        world.changeBoss { $0.hitsLeft = Int(Double($0.hits) * 0.3) }
        world.advance(by: frame, input: PlaneGameInput())
        let boss = try #require(world.boss)
        let copy = try #require(boss.copies.last)
        world.shots.append(
            PlaneGameShot(id: world.takeID(), position: CGPoint(x: copy.x, y: copy.y + boss.radius + 2), drift: 0))
        world.advance(by: frame, input: PlaneGameInput())
        #expect(try #require(world.boss).hitsLeft == boss.hitsLeft - 1)
    }

    @Test func itsBodiesWeaveInsideTheLanes() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(5)
        world.changeBoss { $0.hitsLeft = Int(Double($0.hits) * 0.6) }
        var leads: [CGFloat] = []
        let middle = phoneField.startingPlace.x
        for _ in 0..<Int(PlaneGameRules.listPeriod / frame) {
            world.advance(by: frame, input: PlaneGameInput())
            let boss = try #require(world.boss)
            #expect(boss.bodies.count == 2)
            #expect(boss.bodies.allSatisfy { phoneField.lanes(inset: boss.radius).contains($0.x) })
            #expect(abs(boss.bodies[0].x - middle + (boss.bodies[1].x - middle)) < 0.01)
            leads.append(boss.position.x)
        }
        #expect(try #require(leads.min()) < middle - 50)
        #expect(try #require(leads.max()) > middle + 50)
    }

    @Test func everyBodyForwardsASpamAtOnce() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(17)
        world.things.removeAll()
        world.runUntilBossAttacks(1)
        let boss = try #require(world.boss)
        #expect(boss.bodies.count == 3)
        let spam = world.things.filter { $0.kind == .spam }.map(\.position.x).sorted()
        let under = boss.bodies.map(\.x).sorted()
        #expect(spam.count == 3)
        #expect(zip(spam, under).allSatisfy { abs($0 - $1) < 8 })
    }

    @Test func angryTheLeadSendsBulkMailEveryThirdAttack() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(5)
        world.changeBoss { $0.hitsLeft = Int(Double($0.hits) * 0.6) }
        world.things.removeAll()
        world.runUntilBossAttacks(3)
        let bulk = world.things.filter { $0.kind == .bulk }
        #expect(bulk.count == 1)
        #expect(bulk.first?.hitsLeft == 4)
    }

    @Test(arguments: [5, 11, 17])
    func angryInEveryTierEveryThirdForwardIsBulkMail(number: Int) throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(number)
        world.changeBoss { $0.hitsLeft = Int(Double($0.hits) * 0.6) }
        let boss = try #require(world.boss)
        let forwards = (0..<30).filter { boss.attacker(at: $0) == .mailingList }
        let bulk = forwards.filter { attack in
            boss.mailingListForwards(on: phoneField, attack: attack).contains { $0.kind == .bulk }
        }
        #expect(bulk.count == forwards.count / 3)
    }

    @Test func bulkMailTakesFourShotsAndShelters() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.bulk, by: 150)
        world.addAhead(.spam, by: 400)
        let events = world.run(for: 0.8, input: PlaneGameInput(isFiring: true))
        #expect(events.first == .shotDown(points: 40))
    }

    @Test func itReformsWithAPopAtEveryBodyWhenItClones() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(5)
        world.bursts.removeAll()
        world.changeBoss { $0.hitsLeft = Int(Double($0.hits) * 0.6) }
        world.advance(by: frame, input: PlaneGameInput())
        let bodies = try #require(world.boss).bodies
        #expect(bodies.count == 2)
        #expect(
            bodies.allSatisfy { body in world.bursts.contains { $0.kind == .pop(points: 0) && $0.position == body } })
        world.bursts.removeAll()
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.bursts.isEmpty)
    }

    @Test func beatenItsBodiesFallTogetherAndAreGone() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(11)
        world.beatBoss()
        world.run(for: PlaneGameRules.bossFall / 2)
        #expect(try #require(world.boss).copies.count == 1)
        world.run(for: PlaneGameRules.bossFall)
        #expect(world.boss == nil)
    }
}
