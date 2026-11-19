import Foundation
import MailCore
import Testing

struct DraftShelfTests {
    private let account = AccountID(rawValue: "a")

    private func draft(_ subject: String) -> Draft { Draft(accountID: account, subject: subject) }

    /// A shelf with `drafts` opened in order and each minimized, the last opened first.
    private func shelved(_ drafts: [Draft]) -> DraftShelf<String> {
        var shelf = DraftShelf<String>()
        for draft in drafts {
            shelf.open(draft, in: draft.subject)
            shelf.minimize(draft)
        }
        return shelf
    }

    @Test func startsEmpty() {
        let shelf = DraftShelf<String>()
        #expect(shelf.state == .empty)
        #expect(shelf.entries.isEmpty)
    }

    @Test func openingWritesTheDraft() {
        var shelf = DraftShelf<String>()
        let lunch = draft("Lunch")
        shelf.open(lunch, in: "composer")
        #expect(shelf.state == .writing(lunch.id))
        #expect(shelf.writing?.composer == "composer")
    }

    @Test func minimizingKeepsWhatWasWritten() {
        var shelf = DraftShelf<String>()
        var lunch = draft("Lunch")
        shelf.open(lunch, in: "composer")
        lunch.subject = "Lunch on Friday"
        shelf.minimize(lunch)
        #expect(shelf.state == .minimized)
        #expect(shelf.entries.map(\.draft.subject) == ["Lunch on Friday"])
    }

    @Test func minimizingAnotherDraftDoesNothing() {
        var shelf = DraftShelf<String>()
        let lunch = draft("Lunch")
        shelf.open(lunch, in: "composer")
        shelf.minimize(draft("Other"))
        #expect(shelf.state == .writing(lunch.id))
        #expect(shelf.entries.map(\.draft.subject) == ["Lunch"])
    }

    @Test func openingWhileWritingMinimizesTheOneOpen() {
        var shelf = DraftShelf<String>()
        let lunch = draft("Lunch")
        let budget = draft("Budget")
        shelf.open(lunch, in: "lunch")
        shelf.open(budget, in: "budget")
        #expect(shelf.state == .writing(budget.id))
        #expect(shelf.entries.map(\.composer) == ["budget", "lunch"])
    }

    @Test func openingADraftAlreadyOnTheShelfWritesItRatherThanAddingIt() {
        var shelf = shelved([draft("Lunch")])
        let lunch = shelf.entries[0].draft
        shelf.open(lunch, in: "second composer")
        #expect(shelf.state == .writing(lunch.id))
        #expect(shelf.entries.map(\.composer) == ["Lunch"])
    }

    @Test func shelvedDraftsComeBackMinimizedInOrder() {
        var shelf = DraftShelf<String>()
        let lunch = draft("Lunch")
        shelf.shelve(lunch, in: "Lunch")
        shelf.shelve(draft("Budget"), in: "Budget")
        shelf.shelve(lunch, in: "Lunch again")
        #expect(shelf.state == .minimized)
        #expect(shelf.entries.map(\.composer) == ["Lunch", "Budget"])
    }

    @Test func shelvingWhileWritingKeepsWriting() {
        var shelf = DraftShelf<String>()
        let budget = draft("Budget")
        shelf.open(budget, in: "Budget")
        shelf.shelve(draft("Lunch"), in: "Lunch")
        #expect(shelf.state == .writing(budget.id))
        #expect(shelf.entries.map(\.composer) == ["Budget", "Lunch"])
    }

    @Test func swipingUpOnOneDraftOpensIt() {
        var shelf = shelved([draft("Lunch")])
        shelf.reopen()
        #expect(shelf.state == .writing(shelf.entries[0].id))
    }

    @Test func swipingUpOnSeveralDraftsOffersThem() {
        var shelf = shelved([draft("Lunch"), draft("Budget")])
        shelf.reopen()
        #expect(shelf.state == .choosing)
    }

    @Test func swipingUpWithNothingOnTheShelfDoesNothing() {
        var shelf = DraftShelf<String>()
        shelf.reopen()
        #expect(shelf.state == .empty)
    }

    @Test func choosingWritesThatDraftAndBringsItToTheFront() {
        var shelf = shelved([draft("Lunch"), draft("Budget"), draft("Trip")])
        let lunch = shelf.entries[2].id
        shelf.reopen()
        shelf.choose(lunch)
        #expect(shelf.state == .writing(lunch))
        #expect(shelf.entries.map(\.composer) == ["Lunch", "Trip", "Budget"])
    }

    @Test func choosingSomethingNotOnTheShelfDoesNothing() {
        var shelf = shelved([draft("Lunch")])
        shelf.choose(UUID())
        #expect(shelf.state == .minimized)
    }

    @Test func dismissingTheChoiceLeavesThemMinimized() {
        var shelf = shelved([draft("Lunch"), draft("Budget")])
        shelf.reopen()
        shelf.dismissChoice()
        #expect(shelf.state == .minimized)
    }

    @Test func finishingTheOneOpenLeavesTheRestMinimized() {
        var shelf = shelved([draft("Lunch")])
        let budget = draft("Budget")
        shelf.open(budget, in: "Budget")
        shelf.finish(budget.id)
        #expect(shelf.state == .minimized)
        #expect(shelf.entries.map(\.composer) == ["Lunch"])
    }

    @Test func finishingTheLastDraftEmptiesTheShelf() {
        var shelf = DraftShelf<String>()
        let lunch = draft("Lunch")
        shelf.open(lunch, in: "Lunch")
        shelf.finish(lunch.id)
        #expect(shelf.state == .empty)
        #expect(shelf.entries.isEmpty)
    }

    @Test func finishingAMinimizedDraftKeepsWritingTheOpenOne() {
        var shelf = shelved([draft("Lunch")])
        let lunch = shelf.entries[0].id
        let budget = draft("Budget")
        shelf.open(budget, in: "Budget")
        shelf.finish(lunch)
        #expect(shelf.state == .writing(budget.id))
        #expect(shelf.entries.map(\.composer) == ["Budget"])
    }

    @Test func discardingTheLastChoiceEmptiesTheShelf() {
        var shelf = shelved([draft("Lunch"), draft("Budget")])
        shelf.reopen()
        for id in shelf.entries.map(\.id) { shelf.finish(id) }
        #expect(shelf.state == .empty)
    }

    @Test func discardingOneChoiceKeepsChoosingTheRest() {
        var shelf = shelved([draft("Lunch"), draft("Budget"), draft("Trip")])
        shelf.reopen()
        shelf.finish(shelf.entries[0].id)
        #expect(shelf.state == .choosing)
        #expect(shelf.entries.map(\.composer) == ["Budget", "Lunch"])
    }

    @Test func discardingDownToOneDraftPutsItBackInTheBar() {
        var shelf = shelved([draft("Lunch"), draft("Budget")])
        shelf.reopen()
        shelf.finish(shelf.entries[0].id)
        #expect(shelf.state == .minimized)
        #expect(shelf.entries.map(\.composer) == ["Lunch"])
    }

    // MARK: How many wait minimized

    @Test func anEmptyShelfHasNoneMinimized() {
        #expect(DraftShelf<String>().minimizedCount == 0)
    }

    @Test func theOneBeingWrittenIsNotMinimized() {
        var shelf = DraftShelf<String>()
        shelf.open(draft("Lunch"), in: "Lunch")
        #expect(shelf.minimizedCount == 0)
    }

    @Test func writingOneWithTwoMinimizedCountsTheTwo() {
        var shelf = shelved([draft("Lunch"), draft("Budget")])
        shelf.open(draft("Trip"), in: "Trip")
        #expect(shelf.minimizedCount == 2)
    }

    @Test func allMinimizedCountsThemAll() {
        #expect(shelved([draft("Lunch"), draft("Budget"), draft("Trip")]).minimizedCount == 3)
    }

    @Test func choosingCountsThemAll() {
        var shelf = shelved([draft("Lunch"), draft("Budget")])
        shelf.reopen()
        #expect(shelf.state == .choosing)
        #expect(shelf.minimizedCount == 2)
    }

    @Test func finishingADraftDropsTheCount() {
        var shelf = shelved([draft("Lunch"), draft("Budget")])
        shelf.finish(shelf.entries[0].id)
        #expect(shelf.minimizedCount == 1)
    }
}
