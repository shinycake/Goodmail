import CoreGraphics
import Foundation
import PlaneGame
import Testing

@testable import MailUI

/// What the screen draws of the power-ups and the bosses: the weapon's arc, the boss's line under the score, its
/// flash and its fall.
struct PlaneGameEncounterLookTests {
    private let field = PlaneGameField(
        size: CGSize(width: 402, height: 874), safeTop: 62, safeLeft: 0, safeBottom: 34, safeRight: 0)

    private func boss(_ status: PlaneGameBoss.Status, hitsLeft: Int? = nil) -> PlaneGameBoss {
        var boss = PlaneGameBoss(number: 1, on: field)
        boss.status = status
        boss.hitsLeft = hitsLeft ?? boss.hits
        return boss
    }

    // MARK: The plane's kit

    @Test func singleShotsShowNoArc() {
        #expect(PlaneGameKit(weapon: .single, isWrapped: false, reduceMotion: false).arc == nil)
    }

    @Test func theArcShortensAsTheWeaponsTimeRunsOut() throws {
        let full = try #require(PlaneGameKit(weapon: .spread(remaining: 8), isWrapped: false, reduceMotion: false).arc)
        let half = try #require(PlaneGameKit(weapon: .rapid(remaining: 4), isWrapped: false, reduceMotion: false).arc)
        #expect(full == 1)
        #expect(half == 0.5)
    }

    @Test func theArcBlinksForTheLastTwoSecondsOrHoldsWithReduceMotion() {
        let times = stride(from: 1.99, to: 0, by: -0.01).map { PlaneGameWeapon.rapid(remaining: $0) }
        let blinking = times.map { PlaneGameKit(weapon: $0, isWrapped: false, reduceMotion: false).arc }
        let steady = times.map { PlaneGameKit(weapon: $0, isWrapped: false, reduceMotion: true).arc }
        #expect(blinking.contains(nil))
        #expect(blinking.contains { $0 != nil })
        #expect(!steady.contains(nil))
        let earlier = stride(from: 8, to: 2.01, by: -0.01).map {
            PlaneGameKit(weapon: .spread(remaining: $0), isWrapped: false, reduceMotion: false).arc
        }
        #expect(!earlier.contains(nil))
    }

    // MARK: The line under the score

    @Test func theLineDrawsItselfInAsTheBossSlidesIn() {
        let drawn = stride(from: 0, through: PlaneGameRules.bossArrival, by: 0.1).map {
            PlaneGameBossLine(boss: boss(.arriving(elapsed: $0)), reduceMotion: false).drawn
        }
        #expect(drawn.first == 0)
        #expect(zip(drawn, drawn.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(PlaneGameBossLine(boss: boss(.fighting(sinceAttack: 0)), reduceMotion: false).drawn == 1)
        #expect(PlaneGameBossLine(boss: boss(.arriving(elapsed: 0)), reduceMotion: true).drawn == 1)
    }

    @Test func theLineShortensWithEachHit() {
        let lefts = (0...20).reversed().map {
            PlaneGameBossLine(boss: boss(.fighting(sinceAttack: 0), hitsLeft: $0), reduceMotion: false).left
        }
        #expect(lefts.first == 1)
        #expect(lefts.last == 0)
        #expect(zip(lefts, lefts.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test func theLineFadesAsTheBossFalls() {
        let falling = PlaneGameBossLine(
            boss: boss(.falling(elapsed: PlaneGameRules.bossFall), hitsLeft: 0), reduceMotion: false)
        #expect(falling.opacity == 0)
    }

    // MARK: The boss

    @Test func aStruckBossFlashesBrieflyAndNeverWithReduceMotion() {
        let fighting = boss(.fighting(sinceAttack: 0))
        #expect(PlaneGameBossSprite(boss: fighting, sinceStruck: 0.02, reduceMotion: false).isFlashing)
        #expect(!PlaneGameBossSprite(boss: fighting, sinceStruck: 0.1, reduceMotion: false).isFlashing)
        #expect(!PlaneGameBossSprite(boss: fighting, sinceStruck: nil, reduceMotion: false).isFlashing)
        #expect(!PlaneGameBossSprite(boss: fighting, sinceStruck: 0.02, reduceMotion: true).isFlashing)
    }

    @Test func aBeatenBossShakesComesApartInThreeBurstsAndItsPointsRise() throws {
        let frames = stride(from: 0, to: PlaneGameRules.bossFall, by: 1.0 / 60).map {
            PlaneGameBossSprite(boss: boss(.falling(elapsed: $0), hitsLeft: 0), sinceStruck: nil, reduceMotion: false)
        }
        let rest = boss(.fighting(sinceAttack: 0)).position
        #expect(frames.contains { $0.position.x != rest.x })
        #expect(Set(frames.flatMap(\.bursts).map(\.position.x)).count == 3)
        let first = try #require(frames.first?.points)
        let last = try #require(frames.last?.points)
        #expect(first.value == 250)
        #expect(last.position.y < first.position.y)
        #expect(try #require(frames.last).opacity < 0.1)
    }

    @Test func withReduceMotionABeatenBossHoldsStill() {
        let frames = stride(from: 0, to: PlaneGameRules.bossFall, by: 1.0 / 60).map {
            PlaneGameBossSprite(boss: boss(.falling(elapsed: $0), hitsLeft: 0), sinceStruck: nil, reduceMotion: true)
        }
        let rest = boss(.fighting(sinceAttack: 0)).position
        #expect(frames.allSatisfy { $0.position == rest })
        #expect(frames.allSatisfy { $0.points?.position == rest })
    }
}
