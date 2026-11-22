import MailCore
import Testing

/// Undo of an action on several rows picked with a pointer picks them again, until the window moves on by any other
/// way (R9).
struct PickDepartureTests {
    private let a = navigationRow("a"), b = navigationRow("b"), c = navigationRow("c")
    private var rows: [ThreadSummary.ID] { [a.id, b.id, c.id] }
    private var trashAB: MailChange { MailChange(.action(.trash), on: [a.id, b.id]) }

    private func context(_ setting: AfterRemoval = .next) -> WindowNavigation.Context {
        WindowNavigation.Context(arrangement: .columns, afterRemoval: setting)
    }

    /// A viewer whose list picked `a` and `b` with a pointer and trashed them.
    private func trashedPick(setting: AfterRemoval = .next) -> WindowNavigation {
        var window = WindowNavigation(showing: WindowState())
        _ = window.handle(
            .changed(
                trashAB, reader: nil,
                front: WindowNavigation.Front(rows: rows, pointerPick: [a.id, b.id], mailbox: .inbox)),
            in: context(setting))
        return window
    }

    @Test(arguments: AfterRemoval.allCases)
    func undoRightAfterPicksTheRowsAgain(setting: AfterRemoval) {
        var window = trashedPick(setting: setting)
        #expect(window.handle(.undone(trashAB, rows: rows), in: context(setting)) == [.repick([a.id, b.id])])
        #expect(window.state.reading == nil, "the conversation the action went on to closes for the count")
        #expect(window.handle(.undone(trashAB, rows: rows), in: context(setting)) == [], "once")
    }

    @Test func theRowsLeavingKeepTheWayBack() {
        var window = trashedPick(setting: .list)
        // The list reports its pick emptied as the trashed rows leave.
        _ = window.handle(.route(.selection(count: 0)), in: context(.list))
        #expect(window.handle(.undone(trashAB, rows: rows), in: context(.list)) == [.repick([a.id, b.id])])
    }

    @Test(arguments: [
        WindowNavigation.Event.route(.selection(count: 2)), .route(.mailbox(.starred)),
    ])
    func anyOtherPickOrMoveEndsTheWayBack(move: WindowNavigation.Event) {
        var window = trashedPick(setting: .list)
        _ = window.handle(move, in: context(.list))
        let moved = window.state
        #expect(window.handle(.undone(trashAB, rows: rows), in: context(.list)) == [])
        #expect(window.state == moved)
    }

    @Test func openingAConversationEndsTheWayBack() {
        var window = trashedPick(setting: .list)
        window.open(c, in: .inbox, from: rows, context(.list))
        #expect(window.handle(.undone(trashAB, rows: rows), in: context(.list)) == [])
        #expect(window.state.reading == Reading(c.id, in: .inbox))
    }

    @Test func undoInAnotherListThanThePicksBringsBackOnlyTheRows() {
        var window = WindowNavigation(showing: WindowState())
        let searched = WindowNavigation.Front(
            rows: rows, pointerPick: [a.id, b.id], mailbox: .allMail, searching: true)
        _ = window.handle(.changed(trashAB, reader: nil, front: searched), in: context(.list))
        #expect(
            window.handle(.undone(trashAB, rows: rows, searching: false), in: context(.list)) == [],
            "search ended, so the list behind it doesn't pick search's rows")

        var list = trashedPick(setting: .list)
        #expect(list.handle(.undone(trashAB, rows: rows, searching: true), in: context(.list)) == [])
    }

    @Test func undoOfAnotherChangeLeavesThePick() {
        var window = trashedPick()
        let other = MailChange(.action(.archive), on: [c.id])
        #expect(window.handle(.undone(other, rows: rows), in: context()) == [])
        #expect(window.state.reading == Reading(c.id, in: .inbox))
    }
}
