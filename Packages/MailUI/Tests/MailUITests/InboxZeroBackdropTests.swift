import Testing
import UIKit

@testable import MailUI

/// The scene behind an empty Inbox follows the list's scrolling. UIKit settles a pull into the refreshing position by
/// animating the list's bounds, so the backdrop must move to its new place without an animation of its own, or the
/// scene would travel the distance twice.
@MainActor
struct InboxZeroBackdropTests {
    @Test func followsTheListInsideUIKitsAnimationsWithoutAnimatingItself() throws {
        let scene = UIView()
        let backdrop = InboxZeroBackdrop(scene: scene)
        backdrop.frame = CGRect(x: 0, y: -350, width: 402, height: 874)

        UIView.animate(withDuration: 1) {
            backdrop.center.y = -237 + 437
            backdrop.pull(by: 60)
        }

        #expect(backdrop.layer.animationKeys() == nil)
        #expect(scene.layer.animationKeys() == nil)
        #expect(backdrop.center.y == 200)
        #expect(scene.transform.ty == 60)
    }
}
