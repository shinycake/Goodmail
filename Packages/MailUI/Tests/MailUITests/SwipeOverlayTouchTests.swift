import Testing
import UIKit

@testable import MailUI

@MainActor
struct SwipeOverlayTouchTests {
    /// A touch over the buttons that none of them takes, as while one is busy, reaches the row under them rather
    /// than vanishing into the overlay.
    @Test func aTouchNoButtonTakesFallsThroughToTheRow() {
        let row = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 110))
        let actions = ["archivebox", "trash"].map { symbol in
            SwipeAction(title: symbol, symbol: symbol, tint: .clear, color: .systemBlue) { _ in }
        }
        let overlay = SwipeOverlayView(actions: actions, side: .right)
        overlay.frame = row.bounds
        row.addSubview(overlay)
        overlay.reveal = .tracking(overlay.layout.revealWidth)
        for button in overlay.buttons { button.isUserInteractionEnabled = false }

        let button = overlay.buttons[0]
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: row)
        #expect(row.hitTest(point, with: nil) === row)
    }
}
