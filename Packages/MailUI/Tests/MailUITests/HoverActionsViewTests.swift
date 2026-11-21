import Testing
import UIKit

@testable import MailUI

/// How the quick actions on a hovered row look: quiet glyphs in a row, each lit in its action's color while the pointer
/// is on it or it is pressed.
@MainActor
struct HoverActionsViewTests {
    private let actions = [SwipeChoice.read, .archive, .trash].map { choice in
        HoverAction(face: HoverAction.Face(title: "\(choice)", symbol: "archivebox", choice: choice), run: {})
    }

    private func buttons(_ view: HoverActionsView) -> [HoverActionButton] { view.shownButtons }

    @Test func aButtonRestsInTheSecondaryLabelColor() {
        for button in buttons(HoverActionsView(actions: actions)) {
            #expect(button.configuration?.baseForegroundColor == .secondaryLabel)
        }
    }

    @Test func aButtonLightsUpUnderThePointer() {
        let button = buttons(HoverActionsView(actions: actions))[1]
        button.isUnderPointer = true
        button.updateConfiguration()
        #expect(button.configuration?.baseForegroundColor == SwipeChoice.archive.color)
        button.isUnderPointer = false
        button.updateConfiguration()
        #expect(button.configuration?.baseForegroundColor == .secondaryLabel)
    }

    @Test func buttonsKeepTheirOwnLookOnAMac() {
        // The Mac's own style would draw each as a bordered push button in the accent color.
        #expect(buttons(HoverActionsView(actions: actions)).allSatisfy { $0.preferredBehavioralStyle == .pad })
    }

    @Test func buttonsAreEvenlySpaced() throws {
        let view = HoverActionsView(actions: actions)
        view.frame.size = view.intrinsicContentSize
        view.layoutIfNeeded()
        let frames = buttons(view).map(\.frame)
        let gaps = zip(frames, frames.dropFirst()).map { $1.minX - $0.maxX }
        #expect(Set(gaps).count == 1)
        #expect(try #require(gaps.first) >= 0)
    }
}
