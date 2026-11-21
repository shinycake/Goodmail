import Testing
import UIKit

@testable import MailUI

@MainActor
struct SwipeTrackpadTests {
    /// A Mac trackpad's two-finger swipe arrives as scrolling, so the rows' swipe has to take it as well as touches.
    @Test func aTwoFingerTrackpadSwipeCanSwipeARow() throws {
        let list = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            collectionViewLayout: UICollectionViewCompositionalLayout.list(using: .init(appearance: .plain)))
        let swipes = SwipeActionsController(collectionView: list, rowID: { _ in nil }, indexPath: { _ in nil })
        let pan = try #require(
            list.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first { $0.delegate === swipes })
        #expect(pan.allowedScrollTypesMask.contains(.continuous))
    }
}
