import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Inbox Overload sends walls of spam and every other boss's attack in turn.
struct OverloadTests {
    @Test func itPatrolsAtASteadyPaceAndComesBack() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(6)
        let reach = PlaneGameRules.overloadReach
        let pace = 4 * reach / CGFloat(PlaneGameRules.overloadPeriod)
        var last = try #require(world.boss).position.x
        let start = try #require(world.boss).fightTime
        while try #require(world.boss).fightTime - start < PlaneGameRules.overloadPeriod {
            world.advance(by: frame, input: PlaneGameInput())
            let x = try #require(world.boss).position.x
            #expect(abs(x - last) <= pace * CGFloat(frame) + 0.01)
            last = x
        }
        #expect(abs(last - phoneField.startingPlace.x) < 6)
    }

    @Test func everyOtherAttackIsAWallWithAGapThatMoves() throws {
        let wide = PlaneGameField(size: CGSize(width: 1024, height: 860), lanes: 12...1012, ceiling: 80, row: 720)
        var boss = PlaneGameBoss(number: 6, on: wide)
        boss.status = .fighting(sinceAttack: 0, attacks: 0)
        var gaps: [CGFloat] = []
        for attack in [0, 2, 4] {
            let wall = boss.overloadWall(on: wide, attack: attack)
            #expect(wall.count == 5)
            #expect(Set(wall.map(\.position.y)).count == 1)
            let xs = wall.map(\.position.x).sorted()
            let slots = Set(xs.map { Int((($0 - boss.position.x) / PlaneGameRules.overloadSpacing).rounded()) })
            let empty = Set(-3...3).subtracting(slots).sorted()
            // Two neighbors, so the gap is two slots and the spam either side of it wide.
            #expect(empty.count == 2 && empty[1] == empty[0] + 1)
            gaps.append(CGFloat(empty[0]))
        }
        #expect(gaps == [-3, -1, 1])
    }

    @Test func betweenWallsItBorrowsEveryOtherBossesAttackInTurn() {
        let boss = PlaneGameBoss(number: 6, on: phoneField)
        let attackers = (0..<10).map { boss.attacker(at: $0) }
        #expect(
            attackers == [
                .overload, .junk, .overload, .phisher, .overload, .storm, .overload, .outOfOffice, .overload,
                .mailingList,
            ])
    }

    @Test func itHasThreePhasesEachQuickerThanTheLast() {
        var boss = PlaneGameBoss(number: 6, on: phoneField)
        var waits: [TimeInterval] = []
        for share in [1.0, 0.6, 0.3] {
            boss.hitsLeft = Int(Double(boss.hits) * share)
            waits.append(boss.overloadWait)
        }
        #expect(waits == [1.6, 1.35, 1.1])
    }
}
