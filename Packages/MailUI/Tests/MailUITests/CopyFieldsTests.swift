import MailCore
import Testing
import UIKit

@testable import MailUI

/// The Cc and Bcc lines fold behind the Cc/Bcc button until asked for, or show from the start for a draft that
/// already copies someone; once shown they stay, and the menu stops offering them.
@MainActor
struct CopyFieldsTests {
    private func composer(cc: [Contact] = []) -> ComposeViewController {
        let composer = ComposeViewController(
            viewModel: ComposeViewModel(
                draft: Draft(accountID: AccountID(rawValue: "a"), cc: cc), accountEmail: "me@example.com",
                send: { _, _ in }))
        composer.loadViewIfNeeded()
        return composer
    }

    @Test func aDraftThatCopiesSomeoneOpensWithTheLinesShowing() {
        let composer = composer(cc: [Contact(name: nil, address: "avi@example.com")])
        #expect(composer.copyFields == .shown)
        #expect(!composer.ccRow.isHidden && !composer.bccRow.isHidden)
        guard case .unavailable = composer.answer(to: .showCopyFields) else {
            Issue.record("Show Cc and Bcc is still offered")
            return
        }
    }

    @Test func showingTheLinesKeepsThemAndStopsOfferingThem() throws {
        let composer = composer()
        #expect(composer.copyFields == .folded)
        #expect(composer.ccRow.isHidden && composer.bccRow.isHidden)
        guard case .ready(let perform, _, _) = composer.answer(to: .showCopyFields) else {
            Issue.record("Show Cc and Bcc isn't offered")
            return
        }
        perform()
        #expect(composer.copyFields == .shown)
        #expect(!composer.ccRow.isHidden && !composer.bccRow.isHidden)
        guard case .unavailable = composer.answer(to: .showCopyFields) else {
            Issue.record("Show Cc and Bcc is still offered")
            return
        }
    }
}
