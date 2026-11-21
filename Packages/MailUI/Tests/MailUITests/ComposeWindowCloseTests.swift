import MailCore
import Testing
import UIKit

@testable import MailUI

/// A message's window on the Mac closes with its traffic lights, so the composer adds no Close of its own there; a
/// message moved into a window of its own on iPad keeps its Close.
@MainActor
struct ComposeWindowCloseTests {
    @Test("The composer shows Close unless its window closes it", arguments: [ComposePlacement.sheet, .ownWindow])
    func closeFollowsTheWindow(_ placement: ComposePlacement) {
        let composer = ComposeViewController(
            viewModel: ComposeViewModel(
                draft: Draft(accountID: AccountID(rawValue: "a")), accountEmail: "me@example.com",
                send: { _, _ in }))
        let host = ComposeWindowController(composer: composer, placement: placement) {}
        composer.loadViewIfNeeded()
        let showsClose = (composer.navigationItem.leftBarButtonItems ?? []).contains {
            $0.accessibilityIdentifier == "compose.close"
        }
        #expect(showsClose == (placement == .sheet))
        _ = host
    }

    @Test(
        "A Mac window's Send is a plain glyph with Send Later in the menu bar; elsewhere it's the prominent arrow",
        arguments: [ComposePlacement.sheet, .ownWindow])
    func sendFollowsTheWindow(_ placement: ComposePlacement) throws {
        let composer = ComposeViewController(
            viewModel: ComposeViewModel(
                draft: Draft(accountID: AccountID(rawValue: "a")), accountEmail: "me@example.com",
                send: { _, _ in }))
        let host = ComposeWindowController(composer: composer, placement: placement) {}
        composer.loadViewIfNeeded()
        let send = try #require(composer.navigationItem.rightBarButtonItems?.first)
        #expect(send.accessibilityLabel == "Send")
        switch placement {
        case .ownWindow:
            #expect(send.style == .plain)
            #expect(send.menu == nil)
        case .sheet:
            #expect(send.style == .prominent)
            #expect(send.menu != nil)
        }
        #expect(!send.isEnabled)
        _ = host
    }
}
