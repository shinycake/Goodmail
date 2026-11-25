import Testing
import UIKit

@testable import MailUI

/// A motion lands once: finishing one that already came to rest does nothing.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScrubbedAnimationTests {
    @Test func aMotionFinishedTwiceLandsOnce() async {
        let space = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let moving = UIView()
        space.addSubview(moving)
        var landings: [Bool] = []
        let animation = ScrubbedAnimation(
            distance: 100, heading: .down, in: space, animations: { moving.frame.origin.y = 100 },
            landed: { landings.append($0) })
        animation.run(following: nil)
        animation.finishNow()
        while landings.isEmpty { await Task.yield() }
        animation.finishNow()
        for _ in 0..<10 { await Task.yield() }
        #expect(landings == [true])
    }
}
