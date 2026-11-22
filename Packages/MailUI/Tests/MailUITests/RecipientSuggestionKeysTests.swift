import MailCore
import Testing
import UIKit

@testable import MailUI

/// The people offered under a recipient field can be picked from the keyboard: the first is highlighted, Up and
/// Down move the highlight, and Return or Tab adds the highlighted one rather than what was typed.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RecipientSuggestionKeysTests {
    private let dana = Contact(name: "Dana Levi", address: "dana@example.com")
    private let dan = Contact(name: "Dan Cohen", address: "dan@example.com")
    private let daphne = Contact(name: "Daphne", address: "daphne@example.com")

    @Test func `nobody to offer makes no list`() {
        #expect(SuggestionList([]) == nil)
    }

    @Test func `the first is highlighted, and the highlight stops at the ends`() throws {
        var list = try #require(SuggestionList([dana, dan, daphne]))
        #expect(list.choice == dana)
        list.move(.up)
        #expect(list.choice == dana)
        list.move(.down)
        list.move(.down)
        #expect(list.choice == daphne)
        list.move(.down)
        #expect(list.choice == daphne)
        list.move(.up)
        #expect(list.choice == dan)
    }

    @Test(arguments: [RecipientField.Intent.commit, .complete])
    func `Return or Tab adds the highlighted person`(_ key: RecipientField.Intent) async {
        let (composer, model) = composer(suggesting: [dana, dan, daphne])
        let field = composer.toField
        field.onIntent(.type("da"))
        await suggestions(in: composer)
        #expect(field.offersSuggestions())

        field.onIntent(.highlight(.down))
        field.onIntent(key)
        #expect(model.recipients.to.contacts == [dan])
        #expect(model.recipients.to.typed.isEmpty)
        #expect(!field.offersSuggestions(), "the list goes once someone is added")
    }

    @Test func `Return without people offered makes a recipient of what was typed`() {
        let (composer, model) = composer(suggesting: [])
        composer.toField.onIntent(.type("someone@example.com"))
        composer.toField.onIntent(.commit)
        #expect(model.recipients.to.contacts.map(\.address) == ["someone@example.com"])
    }

    private func composer(suggesting people: [Contact]) -> (ComposeViewController, ComposeViewModel) {
        let model = ComposeViewModel(
            draft: Draft(accountID: AccountID(rawValue: "a")), accountEmail: "me@example.com",
            suggest: { _ in people }, send: { _, _ in })
        let composer = ComposeViewController(viewModel: model)
        composer.loadViewIfNeeded()
        return (composer, model)
    }

    private func suggestions(in composer: ComposeViewController) async {
        while !composer.isSuggesting(under: composer.toField) { await Task.yield() }
    }
}
