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

    private func buttons(_ view: HoverActionsView) -> [HoverActionButton] { view.buttons }

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

    @Test func theCapsuleIsSmallAndHoldsEachButtonWhole() {
        let view = HoverActionsView(actions: actions)
        view.frame.size = view.intrinsicContentSize
        view.layoutIfNeeded()
        #expect(view.bounds.height <= 24)
        for button in buttons(view) {
            #expect(button.frame.size == CGSize(width: 20, height: 20))
            #expect(view.bounds.contains(button.frame))
        }
    }

    /// Each glyph sits inside its face and the capsule at its own 11.5 point size, in either direction. Configured only
    /// through the button's preferred configuration, the symbol came out at the body size, stretched over the face's
    /// whole height and, on the Mac, past the capsule's edge.
    @Test(arguments: [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft])
    func eachGlyphSitsInsideItsFaceAtItsSize(direction: UISemanticContentAttribute) throws {
        let faces = [SwipeChoice.read, .archive, .trash, .spam].map { choice in
            HoverAction(face: HoverAction.Face(title: "\(choice)", symbol: choice.symbol, choice: choice), run: {})
        }
        let view = HoverActionsView(actions: faces)
        view.semanticContentAttribute = direction
        view.frame.size = view.intrinsicContentSize
        view.layoutIfNeeded()
        for button in buttons(view) {
            button.layoutIfNeeded()
            let glyph = try #require(button.imageView)
            let image = try #require(glyph.image)
            let inButton = glyph.convert(glyph.bounds, to: button)
            let stretch = max(abs(inButton.width - image.size.width), abs(inButton.height - image.size.height))
            #expect(stretch < 0.5, "drawn at its own size \(image.size), not stretched to \(inButton.size)")
            #expect(button.bounds.insetBy(dx: 1, dy: 1).contains(inButton), "\(inButton) in \(button.bounds)")
            #expect(view.bounds.contains(glyph.convert(glyph.bounds, to: view)))
            #expect(inButton.height < 17, "an 11.5 point glyph, not \(inButton.height) high")
        }
    }
}
