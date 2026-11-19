import Foundation
import Testing
import UIKit

@testable import MailUI

@MainActor
struct MessageAppearanceTests {
    /// A card whose app around it is in `style`.
    private func card(in style: UIUserInterfaceStyle) -> MessageCardView {
        let card = MessageCardView(attachmentData: { _, _ in Data() })
        set(style, on: card)
        return card
    }

    private func set(_ style: UIUserInterfaceStyle, on card: MessageCardView) {
        card.traitOverrides.userInterfaceStyle = style
        card.updateTraitsIfNeeded()
    }

    /// UIKit hands an override down to subviews on the next trait update, which a card outside a window only gets
    /// when asked.
    private func tap(_ button: UIButton, on card: MessageCardView) {
        button.sendActions(for: .primaryActionTriggered)
        card.updateTraitsIfNeeded()
    }

    @Test func aDarkReaderSwitchesOneMessageToLightAndBack() {
        let card = card(in: .dark)
        let button = card.appearanceButton
        #expect(!button.isHidden)
        #expect(button.accessibilityLabel == MessageAppearance.app.switchTitle)

        tap(button, on: card)
        #expect(button.traitCollection.userInterfaceStyle == .light, "the card's contents read in light")
        #expect(card.traitCollection.userInterfaceStyle == .dark, "the app around it stays dark")
        #expect(!button.isHidden, "the moon stays to switch back")
        #expect(button.accessibilityLabel == MessageAppearance.light.switchTitle)

        tap(button, on: card)
        #expect(button.traitCollection.userInterfaceStyle == .dark)
    }

    @Test func theSwitchShowsOnlyWhileTheAppIsDark() {
        let card = card(in: .light)
        #expect(card.appearanceButton.isHidden)
        set(.dark, on: card)
        #expect(!card.appearanceButton.isHidden)
        set(.light, on: card)
        #expect(card.appearanceButton.isHidden)
    }
}
