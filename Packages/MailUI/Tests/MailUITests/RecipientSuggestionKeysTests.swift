import MailCore
import Testing
import UIKit

@testable import MailUI

/// The people offered under a recipient field can be picked from the keyboard: Up and Down pick one, Return adds the
/// one picked and Tab the picked one or the first. Without a pick, Return keeps what was typed.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RecipientSuggestionKeysTests {
    private let dana = Contact(name: "Dana Levi", address: "dana@example.com")
    private let dan = Contact(name: "Dan Cohen", address: "dan@example.com")
    private let daphne = Contact(name: "Daphne", address: "daphne@example.com")

    @Test func `nobody to offer makes no list`() {
        #expect(SuggestionList([]) == nil)
    }

    @Test func `nobody is picked until an arrow moves, and the pick stops at the ends`() throws {
        var list = try #require(SuggestionList([dana, dan, daphne]))
        #expect(list.picked == nil)
        #expect(list.tabChoice == dana)
        list.move(.up)
        #expect(list.picked == dana)
        list.move(.down)
        list.move(.down)
        #expect(list.picked == daphne)
        list.move(.down)
        #expect(list.picked == daphne)
        list.move(.up)
        #expect(list.picked == dan)
    }

    @Test(arguments: [RecipientField.Intent.commit, .complete])
    func `Return or Tab adds the highlighted person`(_ key: RecipientField.Intent) async {
        let (composer, model) = composer(suggesting: [dana, dan, daphne])
        let field = composer.toField
        field.onIntent(.type("da"))
        await suggestions(in: composer)
        #expect(field.offersSuggestions())

        field.onIntent(.highlight(.down))
        field.onIntent(.highlight(.down))
        field.onIntent(key)
        #expect(model.recipients.to.contacts == [dan])
        #expect(model.recipients.to.typed.isEmpty)
        #expect(!field.offersSuggestions(), "the list goes once someone is added")
    }

    /// A new address that happens to match someone known goes to whoever was typed, on every device.
    @Test func `Return without a pick keeps what was typed`() async {
        let (composer, model) = composer(suggesting: [dana])
        let field = composer.toField
        field.onIntent(.type("dan@example.org"))
        await suggestions(in: composer)
        #expect(field.offersSuggestions())
        field.onIntent(.commit)
        #expect(model.recipients.to.contacts.map(\.address) == ["dan@example.org"])
    }

    @Test func `Tab without a pick adds the first person`() async {
        let (composer, model) = composer(suggesting: [dana, dan])
        let field = composer.toField
        field.onIntent(.type("da"))
        await suggestions(in: composer)
        field.onIntent(.complete)
        #expect(model.recipients.to.contacts == [dana])
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
