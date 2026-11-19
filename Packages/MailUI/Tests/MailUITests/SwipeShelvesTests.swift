import Testing

@testable import MailUI

/// The swipe settings list moves a dropped row before it reports the drop, so what it shows has to take every drop
/// where it fell, even one the arrangement refuses or reorders, until the drag ends.
struct SwipeShelvesTests {
    private let fullRight = SwipeArrangement(left: [.read, .star], right: [.archive, .snooze, .trash])

    @Test func theShelvesShowTheArrangementShelfByShelf() {
        let shelves = SwipeShelves(fullRight)
        #expect(shelves[.side(.left)] == [.read, .star])
        #expect(shelves[.side(.right)] == [.archive, .snooze, .trash])
        #expect(shelves[.unused] == [.spam])
    }

    @Test(arguments: [
        (SwipeChoice.trash, SwipeArrangement.Shelf.side(.left), SwipeChoice?.some(.star)),
        (.star, .side(.right), .archive),
        (.read, .side(.left), nil),
        (.snooze, .unused, .trash),
        (.archive, .side(.right), nil),
    ])
    func aDropTheArrangementTakesLandsWhereTheListPutIt(
        choice: SwipeChoice, shelf: SwipeArrangement.Shelf, anchor: SwipeChoice?
    ) {
        var arrangement = SwipeArrangement.standard
        arrangement.move([.trash], to: .unused)
        var state = SwipeListState.following
        state.drop([choice], on: shelf, before: anchor, into: &arrangement)
        #expect(state == .following)
    }

    @Test func aDropOntoAFullSideShowsWhereItFellUntilTheDragEnds() throws {
        var arrangement = fullRight
        var state = SwipeListState.following
        state.drop([.star], on: .side(.right), before: .archive, into: &arrangement)
        #expect(arrangement == fullRight, "the arrangement refuses a fourth action")
        let shown = try #require(state.shownShelves)
        #expect(shown[.side(.right)] == [.star, .archive, .snooze, .trash])
        #expect(shown[.side(.left)] == [.read])
        state.dragEnded()
        #expect(state == .following)
    }

    @Test func aDropInsideMoreActionsShowsTheDroppedOrderUntilTheDragEnds() throws {
        var arrangement = SwipeArrangement(left: [.read], right: [.archive, .snooze, .trash])
        var state = SwipeListState.following
        state.drop([.spam], on: .unused, before: .star, into: &arrangement)
        #expect(SwipeShelves(arrangement)[.unused] == [.star, .spam], "More Actions keeps the usual order")
        #expect(try #require(state.shownShelves)[.unused] == [.spam, .star])
        state.dragEnded()
        #expect(state.shownShelves == nil)
    }

    @Test func aDropAfterARefusedOneStartsFromWhatTheListShows() throws {
        var arrangement = fullRight
        var state = SwipeListState.following
        state.drop([.star], on: .side(.right), before: .archive, into: &arrangement)
        // A second drop before the first drag's end arrives: the list moved it from where the first one showed.
        state.drop([.read], on: .side(.right), before: nil, into: &arrangement)
        let shown = try #require(state.shownShelves)
        #expect(shown[.side(.right)] == [.star, .archive, .snooze, .trash, .read])
        #expect(shown[.side(.left)].isEmpty)
        #expect(arrangement == fullRight)
    }

    @Test func aDropBeforeOneOfItsOwnChoicesChangesNothing() {
        var shelves = SwipeShelves(fullRight)
        shelves.drop([.read], on: .side(.left), before: .read)
        #expect(shelves == SwipeShelves(fullRight))
    }
}
