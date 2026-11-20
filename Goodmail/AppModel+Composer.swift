import MailCore
import MailStore
import MailUI

extension AppModel {
    /// A composer for `draft`, acting through `actions`, or `nil` once its account is gone. A new message starts with
    /// what another app `shared`, if anything, above the signature.
    func composer(for draft: Draft, shared: String = "", actions: MailActions) -> ComposeViewController? {
        guard let account = accounts.first(where: { $0.id == draft.accountID }) else { return nil }
        let suggester = RecipientSuggester(
            writtenIn: { [database] in try database.contacts(matching: $0) }, addressBook: SystemAddressBook())
        return ComposeViewController(
            viewModel: ComposeViewModel(
                draft: draft, accountEmail: account.email, senders: accounts, shared: shared,
                signature: { [database] in try? database.signature(for: $0) },
                suggest: { await suggester.suggestions(for: $0) },
                saveDraft: { actions.saveDraft($0, $1) }, deleteDraft: { actions.deleteDraft($0) },
                send: { actions.send($0, at: $1) }))
    }
}
