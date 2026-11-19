import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Each time round the roster, bosses come back angrier: more phases, faster, and borrowing each other's attacks.
struct BossTierTests {
    private func boss(_ number: Int, hitsLeftShare share: Double = 1) -> PlaneGameBoss {
        var boss = PlaneGameBoss(number: number, on: phoneField)
        boss.hitsLeft = Int((Double(boss.hits) * share).rounded(.down))
        return boss
    }

    @Test func theRosterComesRoundATierAngrier() {
        #expect((1...6).allSatisfy { boss($0).tier == 0 })
        #expect((7...12).allSatisfy { boss($0).tier == 1 })
        #expect(boss(13).tier == 2)
        let tempos = stride(from: 1, through: 600, by: 6).map { boss($0).tempo }
        #expect(tempos[0] == 1)
        #expect(zip(tempos, tempos.dropFirst()).allSatisfy { $0 < $1 })
        #expect(tempos.allSatisfy { $0 < 1 + PlaneGameRules.bossTempoGain })
    }

    @Test func aBossHasTwoPhasesThenThree() {
        #expect(boss(1).level == 0)
        #expect(boss(1, hitsLeftShare: 0.5).level == 1)
        #expect(boss(7).level == 1)
        #expect(boss(7, hitsLeftShare: 0.6).level == 2)
        #expect(boss(7, hitsLeftShare: 0.3).level == 3)
        #expect(boss(5).phases == 3)
        #expect(boss(6).phases == 3)
        #expect(boss(19, hitsLeftShare: 0.1).level == PlaneGameRules.bossMostLevel)
    }

    @Test(arguments: 1...5)
    func theFirstTimeRoundABossUsesOnlyItsOwnAttack(number: Int) {
        let boss = boss(number)
        #expect((0..<12).allSatisfy { boss.attacker(at: $0) == boss.kind })
    }

    @Test func theSecondTimeRoundEveryThirdAttackIsBorrowedInTurn() {
        let attackers = (0..<9).map { boss(7).attacker(at: $0) }
        #expect(attackers == [.junk, .junk, .phisher, .junk, .junk, .storm, .junk, .junk, .outOfOffice])
    }

    @Test func fromTheThirdTimeRoundEveryOtherAttackIsBorrowed() {
        let attackers = (0..<6).map { boss(13).attacker(at: $0) }
        #expect(attackers == [.junk, .phisher, .junk, .storm, .junk, .outOfOffice])
    }

    @Test func aBorrowedAttackComesFromUnderTheBorrower() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(7)
        world.runUntilBossAttacks(2)
        world.things.removeAll()
        world.runUntilBossAttacks(3)
        let boss = try #require(world.boss)
        let lures = world.things.filter { $0.kind == .lure }
        // The second time round, at level 1: the Phisher's fan of five, cast from under Junk Mail.
        #expect(lures.count == 5)
        #expect(lures.allSatisfy { abs($0.lane - boss.position.x) < 4 })
    }

    @Test func anAngrierBossMovesAndAttacksFaster() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(7)
        let tempo = try #require(world.boss).tempo
        var xs: [CGFloat] = []
        for _ in 0..<Int((PlaneGameRules.junkGlidePeriod / tempo / frame).rounded()) {
            world.advance(by: frame, input: PlaneGameInput())
            xs.append(try #require(world.boss).position.x)
        }
        #expect(abs(xs[xs.count - 1] - phoneField.startingPlace.x) < 6)
        var drops: [TimeInterval] = []
        while drops.count < 3 {
            if !world.newThings(over: frame).isEmpty { drops.append(world.elapsed) }
        }
        #expect(abs(drops[2] - drops[1] - PlaneGameRules.junkAngryDropEvery / tempo) < 1.5 * frame)
    }

    @Test func anAngrierJunkMailDropsUpToFourSideBySide() {
        let drop = boss(7, hitsLeftShare: 0.25).junkDrop(on: phoneField)
        #expect(drop.count == 4)
        #expect(Set(drop.map(\.position.y)).count == 1)
        for (left, right) in zip(drop, drop.dropFirst()) {
            #expect(abs(right.position.x - left.position.x - PlaneGameRules.junkPairSpacing) < 0.001)
        }
    }

    @Test func aRowNearASideMovesInsideTheLanesRatherThanPilingUp() {
        var boss = boss(7, hitsLeftShare: 0.25)
        boss.position.x = phoneField.lanes(inset: boss.radius).lowerBound
        let xs = boss.junkDrop(on: phoneField).map(\.position.x)
        #expect(Set(xs).count == 4)
        #expect(
            xs.allSatisfy {
                phoneField.lanes(inset: PlaneGameThing.Kind.spam.radius + PlaneGameThing.Kind.spam.swing).contains($0)
            })
    }

    @Test func thePhisherCreepsNoFasterInLaterTiersSoItCanStillBeHit() throws {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 150))
        world.meetBoss(14)
        world.run(for: PlaneGameRules.phisherHold)
        let before = try #require(world.boss).position.x
        world.run(for: 0.3)
        #expect(abs(try #require(world.boss).position.x - before) <= PlaneGameRules.phisherCreep * 0.3 + 0.01)
    }

    @Test func aWaitThatShortensMidFightFiresNoBacklog() {
        // Well into a long wait when it turns angry enough that its next waits are echoes'.
        var boss = PlaneGameBoss(number: 9, on: phoneField)
        boss.status = .fighting(sinceAttack: 1.4, attacks: 1)
        boss.hitsLeft = 1
        let sent = (0..<3).map { _ in
            boss.advance(by: frame, towardX: 200, on: phoneField, scroll: 150, attacking: true).count
        }
        #expect(sent.filter { $0 > 0 }.count == 1)
    }

    @Test func anAngrierPhisherCastsAWiderFanWithRoomBetweenLures() {
        for (share, count) in [(1.0, 5), (0.6, 7), (0.3, 9)] {
            let cast = boss(8, hitsLeftShare: share).phisherCast(on: phoneField)
            #expect(cast.count == count)
            let drifts = cast.map(\.drift)
            #expect(zip(drifts, drifts.dropFirst()).allSatisfy { $1 - $0 >= PlaneGameRules.lureGap - 0.001 })
            #expect(drifts[count / 2] == 0)
        }
    }
}
