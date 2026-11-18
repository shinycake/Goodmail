import Foundation
import PlaneGame
import Testing

/// Ten quick taps on the envelope pile open the game.
struct TapStreakTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func theTenthQuickTapFiresAndTheEleventhStartsOver() {
        var streak = TapStreak()
        var fired: [Bool] = []
        for tap in 0..<10 { fired.append(streak.tap(at: start.addingTimeInterval(Double(tap) * 0.2))) }
        #expect(fired == Array(repeating: false, count: 9) + [true])
        let eleventh = streak.tap(at: start.addingTimeInterval(2.1))
        #expect(!eleventh)
    }

    @Test func tenTapsSpreadOverMoreThanTheWindowNeverFire() {
        var streak = TapStreak()
        var fired: [Bool] = []
        for tap in 0..<30 { fired.append(streak.tap(at: start.addingTimeInterval(Double(tap) * 0.35))) }
        #expect(!fired.contains(true))
    }

    @Test func anOldTapFallsOutOfTheCount() {
        var streak = TapStreak(taps: 3, within: 1)
        _ = streak.tap(at: start)
        _ = streak.tap(at: start.addingTimeInterval(0.9))
        let thirdAfterTheFirstLapsed = streak.tap(at: start.addingTimeInterval(1.5))
        let thirdWithinTheWindow = streak.tap(at: start.addingTimeInterval(1.6))
        #expect(!thirdAfterTheFirstLapsed)
        #expect(thirdWithinTheWindow)
    }
}
