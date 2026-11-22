import MailCore
import Testing
import UIKit

@testable import MailUI

/// Mac Catalyst shows no input accessories, so a desktop window keeps the formatting bar in the composer itself;
/// a touch window keeps it above the keyboard.
@MainActor
struct FormattingBarPlacementTests {
    @Test(arguments: [
        (InteractionStyle.touch, FormattingBarPlacement.aboveKeyboard),
        (.desktop, .inWindow),
    ])
    func `the window's style places the bar`(style: InteractionStyle, placement: FormattingBarPlacement) {
        #expect(FormattingBarPlacement(style) == placement)
    }

    @Test(arguments: [InteractionStyle.touch, .desktop])
    func `the composer puts the bar where its window wants it`(style: InteractionStyle) {
        let composer = ComposeViewController(
            viewModel: ComposeViewModel(
                draft: Draft(accountID: AccountID(rawValue: "a")), accountEmail: "me@example.com",
                send: { _, _ in }))
        composer.traitOverrides.interactionStyle = style
        composer.loadViewIfNeeded()
        composer.view.frame = CGRect(x: 0, y: 0, width: 600, height: 700)
        composer.view.layoutIfNeeded()
        switch style {
        case .touch:
            #expect(composer.bodyView.inputAccessoryView === composer.formattingBar)
            #expect(composer.formattingBar.superview == nil)
        case .desktop:
            #expect(composer.bodyView.inputAccessoryView == nil)
            #expect(composer.formattingBar.superview === composer.view)
            #expect(composer.formattingBar.frame.maxY <= composer.view.bounds.maxY)
            #expect(composer.formattingBar.frame.height > 0)
        }
    }
}
