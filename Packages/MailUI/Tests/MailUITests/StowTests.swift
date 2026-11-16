import MailCore
import Testing
import UIKit

@testable import MailUI

@MainActor
struct StowTests {
    @Test(arguments: [(ThreadAction.trash, StowKind.trash), (.archive, .archive)])
    func actionsThatPutAThreadAwayGoIntoTheirBox(action: ThreadAction, box: StowKind) {
        #expect(action.stow == box)
    }

    @Test(arguments: [
        ThreadAction.untrash, .moveToInbox, .reportSpam, .mute, .unmute, .markRead(true), .star(true),
    ])
    func otherActionsJustCloseTheButtons(action: ThreadAction) {
        #expect(action.stow == nil)
    }

    /// The box stands where the symbol was, on a round button and on one stretched by a full swipe, and stays there
    /// when the button lays out again.
    @Test(arguments: [CGSize(width: 64, height: 64), CGSize(width: 320, height: 80)])
    func theBoxTakesTheSymbolsPlace(size: CGSize) {
        let action = SwipeAction(title: "Trash", symbol: "trash", tint: .red, color: .systemRed, stow: .trash) { _ in }
        let button = GlassActionButton(action: action)
        button.frame = CGRect(origin: .zero, size: size)
        button.layoutIfNeeded()
        let symbol = button.symbolCenter

        let box = button.showBox(.trash)
        button.setNeedsLayout()
        button.layoutIfNeeded()

        let center = box.convert(CGPoint(x: box.bounds.midX, y: box.bounds.midY), to: button)
        #expect(abs(center.x - symbol.x) < 0.5 && abs(center.y - symbol.y) < 0.5)
        #expect(box.bounds.size == CGSize(width: 30, height: 30))
    }
}
