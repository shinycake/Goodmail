import MailCore
import MailStore
import MailUI

extension AppModel {
    /// A composer for `draft`, acting through `actions`, or `nil` once its account is gone.
    func composer(for draft: Draft, actions: MailActions) -> ComposeViewController? {
        composer(for: draft, actions: actions, sendingThrough: { actions })
    }

    /// A composer for `draft` that saves and deletes through `actions` and sends through the actions `sendingThrough`
    /// names as it sends, whose toast offers Undo Send; `nil` once its account is gone.
    func composer(
        for draft: Draft, actions: MailActions, sendingThrough: @escaping () -> MailActions
    ) -> ComposeViewController? {
        guard let account = accounts.first(where: { $0.id == draft.accountID }) else { return nil }
        let suggester = RecipientSuggester(
            writtenIn: { [database] typed in try await database.offMain { try $0.contacts(matching: typed) } },
            addressBook: SystemAddressBook())
        return ComposeViewController(
            viewModel: ComposeViewModel(
                draft: draft, accountEmail: account.email, senders: accounts,
                signature: { [weak self] in self?.signatures[$0] },
                suggest: { await suggester.suggestions(for: $0) },
                saveDraft: { actions.saveDraft($0, $1) }, deleteDraft: { actions.deleteDraft($0) },
                send: { sendingThrough().send($0, at: $1) }))
    }
}
