import MailCore
import Testing

/// Undo brings the reader back to the conversation an action took it from, while the window still shows where that
/// left it; anywhere else only the row comes back (R9).
struct DepartureTests {
    private static func row(_ name: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: name)
    }

    private let a = row("a"), b = row("b"), c = row("c")
    private let archiveB = MailChange(.action(.archive), on: [row("b")])

    /// The Inbox, reading `thread`.
    private func inbox(reading thread: ThreadSummary.ID?) -> WindowState {
        var state = WindowState()
        state.setThread(thread)
        return state
    }

    private func facts(reading thread: ThreadSummary.ID, in state: WindowState, setting: AfterRemoval = .next)
        -> ReaderCourse.Facts
    {
        ReaderCourse.Facts(
            reader: ReaderCourse.Reader(thread: thread, mailbox: .inbox, labels: [SystemLabel.inbox]),
            rows: [a, b, c], pointerPick: [], state: state, setting: setting)
    }

    /// The course after the reader archived `b` from an Inbox listing `a`, `b`, `c`, and the window as that left it.
    private func archivedB(setting: AfterRemoval) -> (ReaderCourse, WindowState) {
        var course = ReaderCourse()
        let move = course.asked(archiveB, facts(reading: b, in: inbox(reading: b), setting: setting))
        return (course, move == .opens(c) ? inbox(reading: c) : inbox(reading: nil))
    }

    @Test(arguments: AfterRemoval.allCases)
    func undoWhereTheActionLeftTheWindowReadsTheConversationAgain(setting: AfterRemoval) {
        var (course, landed) = archivedB(setting: setting)
        let back = course.undone(archiveB, in: landed)
        #expect(back?.thread == b)
        #expect(back?.mailbox == .inbox)
        let again = course.undone(archiveB, in: landed)
        #expect(again == nil, "once")
    }

    @Test func undoAfterMovingOnBringsBackOnlyTheRow() {
        var (course, _) = archivedB(setting: .next)
        let afterOpeningAnother = course.undone(archiveB, in: inbox(reading: a))
        #expect(afterOpeningAnother == nil)
        (course, _) = archivedB(setting: .list)
        let afterGoingElsewhere = course.undone(archiveB, in: WindowState(list: .mailbox(.starred, thread: nil)))
        #expect(afterGoingElsewhere == nil)
    }

    @Test func anotherChangeSinceLeavesNothingToReturnTo() {
        var (course, landed) = archivedB(setting: .next)
        let star = MailChange(.action(.star(true)), on: [c])
        let move = course.asked(star, facts(reading: c, in: landed))
        #expect(move == .stays)
        let afterTheStar = course.undone(star, in: landed)
        #expect(afterTheStar == nil, "the star took nobody anywhere")
        let afterTheArchive = course.undone(archiveB, in: landed)
        #expect(afterTheArchive == nil, "Undo takes back the star, not the archive")
    }

    @Test func undoOfAnotherChangeLeavesTheDepartureForItsOwn() {
        var (course, landed) = archivedB(setting: .next)
        let other = course.undone(MailChange(.action(.archive), on: [a]), in: landed)
        #expect(other == nil)
        let own = course.undone(archiveB, in: landed)
        #expect(own?.thread == b)
    }

    @Test func markAsUnreadReturnsOnUndoToo() {
        var course = ReaderCourse()
        let unread = MailChange(.action(.markRead(false)), on: [b])
        let move = course.asked(unread, facts(reading: b, in: inbox(reading: b)))
        #expect(move == .closes)
        let back = course.undone(unread, in: inbox(reading: nil))
        #expect(back?.thread == b)
    }

    @Test func aMessageWindowKeepsItsOwnUndo() {
        var course = ReaderCourse()
        let window = WindowState().opening(b, in: .inbox, as: .message)
        let move = course.asked(archiveB, facts(reading: b, in: window))
        #expect(move == .leavesWindow)
        let back = course.undone(archiveB, in: window)
        #expect(back == nil)
    }
}
