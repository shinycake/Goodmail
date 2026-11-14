import CoreGraphics
import Testing

@testable import MailUI

struct SwipeStateTests {
    private struct Row: Identifiable, Equatable {
        let id: String
        let side: SwipeSide
    }

    private let layout = SwipeLayout(count: 2, rowWidth: 402)
    /// Row "a" revealing its right side, as a leftward drag does.
    private let a = Row(id: "a", side: .right)

    /// The rows a drag revealed, by side; a side missing here has no actions.
    private func reveal(_ id: String, sides: [SwipeSide] = [.left, .right]) -> (SwipeSide) -> Row? {
        { side in sides.contains(side) ? Row(id: id, side: side) : nil }
    }

    /// `id` with its buttons settled open on `side`.
    private func opened(_ id: String, on side: SwipeSide) -> SwipeState<Row> {
        var state = SwipeState<Row>.idle
        _ = state.begin(on: id, heading: side.towardEdge, reveal: reveal(id))
        _ = state.end(
            afterMoving: side.towardEdge * layout.revealWidth, velocity: 0, layout: layout, cancelled: false)
        return state
    }

    @Test func aDragRevealsTheSideItHeadsTo() {
        var state = SwipeState<Row>.idle
        #expect(state.begin(on: "a", heading: -5, reveal: reveal("a")) == nil)
        #expect(state.row == Row(id: "a", side: .right))
        #expect(state.distance(afterMoving: -50) == 50)
    }

    @Test func aDragTowardASideWithoutActionsRevealsNothing() {
        var state = SwipeState<Row>.idle
        _ = state.begin(on: "a", heading: 5, reveal: reveal("a", sides: [.right]))
        #expect(state.row == nil)
        #expect(state.distance(afterMoving: 50) == nil)
    }

    @Test(arguments: [SwipeSide.left, .right])
    func releasingPastHalfwayOpensTheButtons(side: SwipeSide) {
        #expect(opened("a", on: side) == .open(Row(id: "a", side: side), side, width: layout.revealWidth))
    }

    @Test func releasingShortOfHalfwayCloses() {
        var state = SwipeState<Row>.idle
        _ = state.begin(on: "a", heading: -5, reveal: reveal("a"))
        #expect(state.end(afterMoving: -20, velocity: 0, layout: layout, cancelled: false) == .closed(a))
        #expect(state == .idle)
    }

    @Test func aFastFlickOpensEvenShortOfHalfway() {
        var state = SwipeState<Row>.idle
        _ = state.begin(on: "a", heading: -5, reveal: reveal("a"))
        let end = state.end(afterMoving: -20, velocity: -800, layout: layout, cancelled: false)
        #expect(end == .opened(a, width: layout.revealWidth))
    }

    @Test func swipingFarEnoughFiresTheEdgeMostAction() {
        var state = SwipeState<Row>.idle
        _ = state.begin(on: "a", heading: -5, reveal: reveal("a"))
        #expect(state.end(afterMoving: -350, velocity: 0, layout: layout, cancelled: false) == .fired(a))
        #expect(state == .idle)
    }

    @Test func aCancelledDragClosesHoweverFarItWent() {
        var state = SwipeState<Row>.idle
        _ = state.begin(on: "a", heading: -5, reveal: reveal("a"))
        #expect(state.end(afterMoving: -350, velocity: 0, layout: layout, cancelled: true) == .closed(a))
    }

    @Test(arguments: [SwipeSide.left, .right])
    func draggingTheOpenRowBackOnlyClosesIt(side: SwipeSide) {
        var state = opened("a", on: side)
        var revealed: [SwipeSide] = []
        let replaced = state.begin(on: "a", heading: -side.towardEdge) { side in
            revealed.append(side)
            return Row(id: "a", side: side)
        }
        #expect(replaced == nil && revealed.isEmpty)
        #expect(state.row == Row(id: "a", side: side))
        // The buttons follow the finger back, and pulling past closed doesn't cross over.
        #expect(state.distance(afterMoving: -side.towardEdge * 30) == layout.revealWidth - 30)
        #expect(state.distance(afterMoving: -side.towardEdge * 400) == 0)
        let end = state.end(afterMoving: -side.towardEdge * 400, velocity: 0, layout: layout, cancelled: false)
        #expect(end == .closed(Row(id: "a", side: side)))
    }

    @Test func aFreshDragAfterClosingRevealsTheOtherSide() {
        var state = opened("a", on: .right)
        _ = state.begin(on: "a", heading: 5, reveal: reveal("a"))
        _ = state.end(afterMoving: 400, velocity: 0, layout: layout, cancelled: false)
        _ = state.begin(on: "a", heading: 5, reveal: reveal("a"))
        #expect(state.row == Row(id: "a", side: .left))
    }

    @Test func draggingTheOpenRowFurtherCarriesOnFromOpen() {
        var state = opened("a", on: .right)
        _ = state.begin(on: "a", heading: -5, reveal: reveal("a"))
        #expect(state.distance(afterMoving: -40) == layout.revealWidth + 40)
    }

    @Test func draggingAnotherRowTakesOverFromTheOpenOne() {
        var state = opened("a", on: .right)
        let replaced = state.begin(on: "b", heading: 5, reveal: reveal("b"))
        #expect(replaced == Row(id: "a", side: .right))
        #expect(state.row == Row(id: "b", side: .left))
    }

    @Test func closingReturnsTheRowThatShowed() {
        var state = opened("a", on: .left)
        #expect(state.close() == Row(id: "a", side: .left))
        #expect(state.close() == nil)
    }
}
