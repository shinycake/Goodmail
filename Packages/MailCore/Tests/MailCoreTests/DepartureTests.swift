import MailCore
import Testing

/// Undo brings the reader back to the conversation an action took it from, until the window moves on by any other
/// way; after that only the row comes back (R9).
struct DepartureTests {
    private let a = navigationRow("a"), b = navigationRow("b"), c = navigationRow("c")
    private var rows: [ThreadSummary.ID] { [a.id, b.id, c.id] }
    private let archiveB = MailChange(.action(.archive), on: [navigationRow("b").id])

    private func context(_ setting: AfterRemoval = .next) -> WindowNavigation.Context {
        WindowNavigation.Context(arrangement: .stack, afterRemoval: setting)
    }

    private func changed(_ change: MailChange, on shown: ThreadSummary) -> WindowNavigation.Event {
        .changed(
            change, reader: WindowNavigation.Reader(shown, mailbox: .inbox, labels: [SystemLabel.inbox]),
            front: WindowNavigation.Front(rows: rows, mailbox: .inbox))
    }

    /// A window that opened `b` from an Inbox listing `a`, `b`, `c` and archived it.
    private func archivedB(setting: AfterRemoval = .next) -> WindowNavigation {
        var window = WindowNavigation(showing: WindowState())
        window.open(b, in: .inbox, from: rows, context(setting))
        _ = window.handle(changed(archiveB, on: b), in: context(setting))
        return window
    }

    @Test(arguments: AfterRemoval.allCases)
    func undoRightAfterReadsTheConversationAgain(setting: AfterRemoval) {
        var window = archivedB(setting: setting)
        _ = window.handle(.undone(archiveB, rows: rows), in: context(setting))
        #expect(window.state.reading == Reading(b.id, in: .inbox))
        #expect(window.foundRow == b, "the row as the reader read it, so nothing is read from the store")
        _ = window.handle(.back(to: .list), in: context(setting))
        _ = window.handle(.undone(archiveB, rows: rows), in: context(setting))
        #expect(window.state.reading == nil, "once")
    }

    @Test func undoAfterOpeningAnotherAndComingBackBringsBackOnlyTheRow() {
        var window = archivedB()
        // It landed on c; the reader opened a, then c again, so the window shows what the archive left.
        window.open(a, in: .inbox, from: rows, context())
        window.open(c, in: .inbox, from: rows, context())
        _ = window.handle(.undone(archiveB, rows: rows), in: context())
        #expect(window.state.reading == Reading(c.id, in: .inbox))
    }

    @Test(arguments: [
        WindowNavigation.Event.route(.mailbox(.starred)), .back(to: .list), .filter(.on([.unread])),
        .category(.social), .route(.search(SearchQuery(terms: []))),
        .accounts([]), .handedOff(WindowState(), accounts: [AccountID(rawValue: "a")]),
    ])
    func anyOtherMoveBringsBackOnlyTheRow(move: WindowNavigation.Event) {
        var window = archivedB()
        _ = window.handle(move, in: context())
        let moved = window.state
        _ = window.handle(.undone(archiveB, rows: rows), in: context())
        #expect(window.state == moved)
    }

    @Test(arguments: [
        WindowNavigation.Event.filter(.none), .category(.primary), .back(to: .list), .missing(navigationRow("d").id),
        .accounts([AccountID(rawValue: "a")]),
        .lists(.init(labels: [], smartMailboxes: []), accounts: [AccountID(rawValue: "a")]),
    ])
    func aMoveThatChangesNothingKeepsTheWayBack(move: WindowNavigation.Event) {
        var window = archivedB(setting: .list)
        _ = window.handle(move, in: context(.list))
        _ = window.handle(.undone(archiveB, rows: rows), in: context(.list))
        #expect(window.state.reading == Reading(b.id, in: .inbox))
    }

    @Test func aHandOffOfWhatShowsAlreadyKeepsTheWayBack() {
        var window = archivedB()
        _ = window.handle(.handedOff(window.state, accounts: [AccountID(rawValue: "a")]), in: context())
        _ = window.handle(.undone(archiveB, rows: rows), in: context())
        #expect(window.state.reading == Reading(b.id, in: .inbox))
    }

    @Test func undoAfterPickingSeveralSinceBringsBackOnlyTheRow() {
        var window = archivedB()
        let columns = WindowNavigation.Context(arrangement: .columns)
        _ = window.handle(.route(.selection(count: 2)), in: columns)
        _ = window.handle(.undone(archiveB, rows: rows), in: columns)
        #expect(window.state.reading == nil, "Undo doesn't replace a Mac's count of picked rows")
    }

    @Test func aScreenPresentedOrTheSameConversationAgainKeepsTheWayBack() {
        var window = archivedB()
        _ = window.handle(.route(.move([c.id], from: .inbox)), in: context())
        _ = window.handle(.route(.thread(c.id, in: .inbox)), in: context())
        _ = window.handle(.undone(archiveB, rows: rows), in: context())
        #expect(window.state.reading == Reading(b.id, in: .inbox))
    }

    @Test func readingOnWhereTheArchiveLandedKeepsTheWayBack() {
        var window = archivedB()
        // A change is asked only of the conversation on show, which is where the archive landed.
        _ = window.handle(.undone(MailChange(.action(.archive), on: [a.id]), rows: rows), in: context())
        _ = window.handle(.undone(archiveB, rows: rows), in: context())
        #expect(
            window.state.reading == Reading(b.id, in: .inbox), "an Undo for another change leaves this one's way back")

        var starred = archivedB()
        let star = MailChange(.action(.star(true)), on: [c.id])
        _ = starred.handle(changed(star, on: c), in: context())
        #expect(starred.state.reading == Reading(c.id, in: .inbox))
        _ = starred.handle(.undone(star, rows: rows), in: context())
        _ = starred.handle(.undone(archiveB, rows: rows), in: context())
        #expect(starred.state.reading == Reading(c.id, in: .inbox), "Undo takes back the star, not the archive")
    }

    @Test func markAsUnreadReturnsOnUndoToo() {
        var window = WindowNavigation(showing: WindowState())
        window.open(b, in: .inbox, from: rows, context())
        let unread = MailChange(.action(.markRead(false)), on: [b.id])
        _ = window.handle(changed(unread, on: b), in: context())
        #expect(window.state.reading == nil)
        _ = window.handle(.undone(unread, rows: rows), in: context())
        #expect(window.state.reading == Reading(b.id, in: .inbox))
    }

    @Test func undoGoesOnFromTheRowsListedThen() {
        var window = archivedB()
        _ = window.handle(.undone(archiveB, rows: [a.id, b.id]), in: context())
        _ = window.handle(changed(archiveB, on: b), in: context())
        #expect(window.state.reading == Reading(c.id, in: .inbox), "c is the front's row below b")
        _ = window.handle(.undone(archiveB, rows: [a.id, b.id]), in: context())
        _ = window.handle(
            .changed(
                archiveB, reader: WindowNavigation.Reader(b, mailbox: .inbox, labels: [SystemLabel.inbox]),
                front: WindowNavigation.Front(rows: [a.id, c.id], mailbox: .inbox)),
            in: context())
        #expect(window.state.reading == Reading(a.id, in: .inbox), "b left the rows: the trail from Undo places it")
    }

    @Test func onlyTheReadersOwnCourseMovesTheWindowByItself() {
        #expect(changed(archiveB, on: b).movesByItself)
        #expect(WindowNavigation.Event.undone(archiveB, rows: rows).movesByItself)
        #expect(!WindowNavigation.Event.found(b, rows: rows).movesByItself, "a tap or a click")
        #expect(!WindowNavigation.Event.back(to: .list).movesByItself)
    }

    @Test func aMessageWindowKeepsItsOwnUndo() {
        var window = WindowNavigation(showing: WindowState(place: .message(Reading(b.id, in: .inbox))))
        #expect(window.handle(changed(archiveB, on: b), in: context()) == [.leaveWindow])
        let before = window
        _ = window.handle(.undone(archiveB, rows: rows), in: context())
        #expect(window == before)
    }
}
