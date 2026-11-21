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
}
