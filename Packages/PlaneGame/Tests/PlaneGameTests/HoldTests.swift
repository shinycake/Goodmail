import Foundation
import PlaneGame
import Testing

/// A paused game's hold: the pause card, the question before leaving for new mail, and the countdown to carry on.
struct HoldTests {
    @Test func resumingFromTheCardCountsDownThreeSeconds() {
        #expect(PlaneGameHold.card.resumed == .countingDown(left: 3))
    }

    @Test func theCountdownShowsThreeTwoOneThenLetsGo() {
        var hold: PlaneGameHold? = PlaneGameHold.counting
        var shown: [Int] = []
        // Quarter seconds add up exactly, so the last step lands on the end.
        for _ in 0..<11 {
            if let count = hold?.count, shown.last != count { shown.append(count) }
            hold = hold?.advanced(by: 0.25)
        }
        #expect(shown == [3, 2, 1])
        #expect(hold == .countingDown(left: 0.25))
        #expect(hold?.advanced(by: 0.25) == nil)
    }

    @Test(arguments: [PlaneGameHold.card, .askingToLeave(staying: .card), .askingToLeave(staying: .countdown)])
    func onlyACountdownMovesWithTime(hold: PlaneGameHold) {
        #expect(hold.advanced(by: 10) == hold)
    }

    @Test func aPauseDuringTheCountdownGoesBackToTheCard() {
        #expect(PlaneGameHold.countingDown(left: 1.5).paused == .card)
    }

    @Test func aPauseLeavesAnUnansweredQuestionUp() {
        let asking = PlaneGameHold.askingToLeave(staying: .countdown)
        #expect(asking.paused == asking)
    }

    @Test func stayingAfterTheQuestionFromTheCardGoesBackToTheCard() {
        #expect(PlaneGameHold.card.askingToLeave.stayed == .card)
    }

    @Test func stayingAfterTheQuestionDuringACountdownCountsDownFromTheStart() {
        #expect(PlaneGameHold.countingDown(left: 0.4).askingToLeave.stayed == .countingDown(left: 3))
    }

    @Test func askingTwiceKeepsWhereStayingGoesBack() {
        let asking = PlaneGameHold.card.askingToLeave
        #expect(asking.askingToLeave == asking)
    }

    @Test func thereIsNoCountWithoutACountdown() {
        #expect(PlaneGameHold.card.count == nil)
        #expect(PlaneGameHold.askingToLeave(staying: .countdown).count == nil)
    }
}
