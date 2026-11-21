import MailCore
import Testing
import UIKit

@testable import MailUI

/// What a composer's host keeps of the message, to bring it back after the app is closed or crashes, follows each
/// version autosave keeps, not only the moments the host itself changes or leaves the screen.
@MainActor
struct ComposerKeptTests {
    @Test func theHostKeepsEachVersionAutosaveKeeps() async {
        var saved: [String?] = []
        let model = ComposeViewModel(
            draft: Draft(accountID: AccountID(rawValue: "a")), accountEmail: "me@example.com",
            saveDraft: { draft, _ in saved.append(draft.body.plain) }, autosavePause: .zero, send: { _, _ in })
        var kept = 0
        let host = ComposeWindowController(
            composer: ComposeViewController(viewModel: model), placement: .sheet, kept: { kept += 1 }, closed: {})

        model.edited { MessageBody(plain: "Hi") }
        await model.settleAutosave()
        #expect(saved == ["Hi"])
        #expect(kept == 1)

        model.edited { MessageBody(plain: "Hi there") }
        await model.settleAutosave()
        #expect(kept == 2)
        _ = host
    }

    @Test func nothingUnchangedIsKeptSoTheHostHearsNothing() async {
        let model = ComposeViewModel(
            draft: Draft(accountID: AccountID(rawValue: "a")), accountEmail: "me@example.com",
            saveDraft: { _, _ in }, autosavePause: .zero, send: { _, _ in })
        var kept = 0
        let host = ComposeWindowController(
            composer: ComposeViewController(viewModel: model), placement: .sheet, kept: { kept += 1 }, closed: {})

        model.edited { model.draft.body }
        await model.settleAutosave()
        #expect(kept == 0)
        _ = host
    }
}
