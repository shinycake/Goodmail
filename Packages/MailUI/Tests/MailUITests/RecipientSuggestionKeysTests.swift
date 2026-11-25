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
        #expect(field.offersSuggestions(.down) && field.offersSuggestions(.tab))

        field.onIntent(.highlight(.down))
        field.onIntent(.highlight(.down))
        field.onIntent(key)
        #expect(model.recipients.to.contacts == [dan])
        #expect(model.recipients.to.typed.isEmpty)
        #expect(!field.offersSuggestions(.tab), "the list goes once someone is added")
    }

    /// A new address that happens to match someone known goes to whoever was typed, on every device.
    @Test func `Return without a pick keeps what was typed`() async {
        let (composer, model) = composer(suggesting: [dana])
        let field = composer.toField
        field.onIntent(.type("dan@example.org"))
        await suggestions(in: composer)
        #expect(field.offersSuggestions(.tab))
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

    /// Holds the lookup for one text until the test lets it go.
    @MainActor
    final class SlowLookup {
        private(set) var waiting: CheckedContinuation<Void, Never>?

        func hold() async {
            await withCheckedContinuation { waiting = $0 }
        }

        func release() {
            waiting?.resume()
            waiting = nil
        }
    }

    private let john = Contact(name: "John", address: "john@example.com")
    private let joan = Contact(name: "Joan", address: "joan@example.com")

    /// A composer that finds John and Joan for "jo", and only Joan for "joan", once `slow` lets that lookup go.
    private func composer(holding slow: SlowLookup) -> (ComposeViewController, ComposeViewModel) {
        let (john, joan) = (john, joan)
        let model = ComposeViewModel(
            draft: Draft(accountID: AccountID(rawValue: "a")), accountEmail: "me@example.com",
            suggest: { typed in
                guard typed == "joan" else { return [john, joan] }
                await slow.hold()
                return [joan]
            }, send: { _, _ in })
        let composer = ComposeViewController(viewModel: model)
        composer.loadViewIfNeeded()
        return (composer, model)
    }

    /// The people found for "jo" stay on show while "joan" is looked up, but nobody is added from them: Tab waits
    /// for the answer and adds the first person found for "joan". Up and Down meanwhile stay with the text.
    @Test func `Tab during a lookup adds from what it finds`() async {
        let slow = SlowLookup()
        let (composer, model) = composer(holding: slow)
        let field = composer.toField
        field.onIntent(.type("jo"))
        await suggestions(in: composer)

        field.onIntent(.type("joan"))
        while slow.waiting == nil { await Task.yield() }
        #expect(field.offersSuggestions(.tab), "Tab waits for the list rather than leaving the field")
        #expect(!field.offersSuggestions(.down), "the earlier list can't be picked from")
        field.onIntent(.complete)
        #expect(model.recipients.to.contacts.isEmpty, "nobody added from the list for \"jo\"")

        slow.release()
        while model.recipients.to.contacts.isEmpty { await Task.yield() }
        #expect(model.recipients.to.contacts == [joan])
        #expect(model.recipients.to.typed.isEmpty)
    }

    /// Someone picked with Down stays picked when the lookup for more letters finds them too, and Return pressed
    /// meanwhile adds them once it answers.
    @Test func `Return during a lookup adds the person still picked`() async {
        let slow = SlowLookup()
        let (composer, model) = composer(holding: slow)
        let field = composer.toField
        field.onIntent(.type("jo"))
        await suggestions(in: composer)
        field.onIntent(.highlight(.down))
        field.onIntent(.highlight(.down))

        field.onIntent(.type("joan"))
        while slow.waiting == nil { await Task.yield() }
        field.onIntent(.commit)
        #expect(model.recipients.to.contacts.isEmpty)

        slow.release()
        while model.recipients.to.contacts.isEmpty { await Task.yield() }
        #expect(model.recipients.to.contacts == [joan])
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
