import SwiftUI
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

    /// A sidebar floating over the list covers its leading side, which is the right in a right-to-left layout.
    @Test(arguments: [false, true])
    func theSceneKeepsClearOfTheBarsAndOfASidebarOverTheList(rightToLeft: Bool) {
        let bars = UIEdgeInsets(top: 116, left: 0, bottom: 83, right: 0)
        let sides = UIEdgeInsets(
            top: 24, left: rightToLeft ? 0 : 280, bottom: 20, right: rightToLeft ? 280 : 0)
        #expect(
            EdgeInsets(bars: bars, sides: sides, rightToLeft: rightToLeft)
                == EdgeInsets(top: 116, leading: 280, bottom: 83, trailing: 0))
    }
}
