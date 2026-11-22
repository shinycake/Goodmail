import MailCore
import Testing

@testable import MailUI

/// Search results in a desktop window pick with the pointer, show hover actions and take the list's keys, as the
/// window's mailboxes do.
@MainActor
struct SearchResultsInteractionTests {
    private func results(_ interaction: InteractionStyle) -> SearchResultsController {
        let search = ThreadSearch(
            local: { _, _ in AsyncThrowingStream { $0.finish() } }, remote: { _, _ in SearchPage() },
            pause: .seconds(60))
        return SearchResultsController(
            search: search, accounts: [], navigate: { _ in }, actions: nil, interaction: interaction)
    }

    @Test(arguments: [InteractionStyle.desktop, .touch])
    func theResultsListTakesTheWindowsInteraction(_ interaction: InteractionStyle) {
        #expect(results(interaction).list.viewModel.interaction == interaction)
    }
}
