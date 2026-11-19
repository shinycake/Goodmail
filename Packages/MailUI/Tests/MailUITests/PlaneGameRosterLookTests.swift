import CoreGraphics
import Foundation
import PlaneGame
import SwiftUI
import Testing

@testable import MailUI

/// What the screen draws of the later bosses: every body, Out of Office's sign, and each boss's title.
struct PlaneGameRosterLookTests {
    private let field = PlaneGameField(
        size: CGSize(width: 402, height: 874), safeTop: 62, safeLeft: 0, safeBottom: 34, safeRight: 0)

    @Test func everyBossHasArtAboutItsSizeAndAName() {
        let kinds = PlaneGameBoss.Kind.allCases
        for (number, kind) in zip(1..., kinds) {
            let boss = PlaneGameBoss(number: number, on: field)
            #expect(boss.kind == kind)
            #expect(!PlaneGameArt.boss(kind).line.isEmpty)
            #expect(abs(PlaneGameArt.size(of: kind) / 2 - boss.radius) <= 10)
        }
        #expect(Set(kinds.map(PlaneGameBossName.of)).count == kinds.count)
    }

    @Test func aBeatenMailingListShakesEveryBodyAlike() throws {
        var boss = PlaneGameBoss(number: 5, on: field)
        boss.copies = [CGPoint(x: 100, y: boss.position.y), CGPoint(x: 300, y: boss.position.y)]
        boss.status = .falling(elapsed: 0.1)
        let sprite = PlaneGameBossSprite(boss: boss, sinceStruck: nil, reduceMotion: false)
        let shake = sprite.position.x - boss.position.x
        #expect(shake != 0)
        #expect(sprite.copies.map(\.x) == [100 + shake, 300 + shake])
    }

    @Test func outOfOfficesSignShowsAndDimsItsLineOnlyWhileItIsUp() {
        var boss = PlaneGameBoss(number: 4, on: field)
        boss.status = .fighting(sinceAttack: 0, attacks: 0)
        #expect(PlaneGameBossSprite(boss: boss, sinceStruck: nil, reduceMotion: false).isShielded)
        #expect(PlaneGameBossLine(boss: boss, reduceMotion: false).opacity == PlaneGameBossLine.shieldedOpacity)
        boss.status = .fighting(sinceAttack: PlaneGameRules.oooSignUpFor, attacks: 0)
        #expect(!PlaneGameBossSprite(boss: boss, sinceStruck: nil, reduceMotion: false).isShielded)
        #expect(PlaneGameBossLine(boss: boss, reduceMotion: false).opacity == 1)
        boss.status = .falling(elapsed: 0)
        #expect(!PlaneGameBossSprite(boss: boss, sinceStruck: nil, reduceMotion: false).isShielded)
    }

    @Test func theTitleFadesInStaysAndFadesBeforeTheFirstAttack() {
        #expect(PlaneGameBossTitleBeat(age: 0, reduceMotion: false).opacity == 0)
        for age in stride(from: 0.25, through: 1.6, by: 0.05) {
            #expect(PlaneGameBossTitleBeat(age: age, reduceMotion: false).opacity == 1)
        }
        #expect(PlaneGameBossTitleBeat(age: 2, reduceMotion: false).opacity == 0)
        #expect(PlaneGameBossTitleBeat(age: 0.1, reduceMotion: false).scale > 1)
        for age in stride(from: 0, through: 2, by: 0.05) {
            #expect(PlaneGameBossTitleBeat(age: age, reduceMotion: true).scale == 1)
        }
    }

    @Test func aLaterTierHasMoreAngerMarksUpToThreeAndTheyStayOnScreen() {
        let marks = (-1...4).map(PlaneGameArt.anger(marks:))
        #expect(marks[0].isEmpty && marks[1].isEmpty)
        #expect(marks[2].boundingRect.height < marks[3].boundingRect.height)
        #expect(marks[3].boundingRect.height < marks[4].boundingRect.height)
        #expect(marks[4] == marks[5])
        // The widest boss at the side of the lanes, which keep 12 points from the edge, keeps its marks on screen.
        let widest = PlaneGameBoss.Kind.overload
        let reach = abs(marks[4].boundingRect.minX) * PlaneGameArt.size(of: widest)
        #expect(reach <= PlaneGameBoss(number: 6, on: field).radius + 12)
    }

    @Test func theTitleIsGoneBeforeAnyFirstBossAttacks() {
        let title = PlaneGameBossTitleBeat.staysFor + PlaneGameBossTitleBeat.fadeOut
        let quickest =
            [
                PlaneGameRules.junkDropEvery, PlaneGameRules.phisherCastEvery, PlaneGameRules.stormReplyEvery,
                PlaneGameRules.oooEvery, PlaneGameRules.listEvery, PlaneGameRules.overloadEvery,
            ].min() ?? 0
        #expect(title <= PlaneGameRules.bossArrival + quickest)
    }
}
