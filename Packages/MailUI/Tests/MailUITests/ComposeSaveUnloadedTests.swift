import MailCore
import Testing
import UIKit

@testable import MailUI

@MainActor
@Suite("Saving a message whose editor never opened")
struct ComposeSaveUnloadedTests {
    @Test("A restored draft saved without opening keeps what it says")
    func keepsItsContent() throws {
        var saved: [Draft] = []
        let draft = Draft(
            accountID: AccountID(rawValue: "a"), subject: "Lunch", body: MessageBody(plain: "See you at noon"))
        let composer = ComposeViewController(
            viewModel: ComposeViewModel(
                draft: draft, accountEmail: "me@example.com", saveDraft: { draft, _ in saved.append(draft) },
                send: { _, _ in }))
        #expect(!composer.isViewLoaded)
        composer.saveDraft()
        let kept = try #require(saved.last)
        #expect(kept.subject == "Lunch")
        #expect(kept.body.plain?.contains("See you at noon") == true)
    }
}
