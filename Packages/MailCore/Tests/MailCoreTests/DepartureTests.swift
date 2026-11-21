import MailCore
import Testing

/// Undo brings the reader back to the conversation an action took it from, until the window moves on by any other
/// way; after that only the row comes back (R9).
struct DepartureTests {
    private static func row(_ name: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: name)
    }

    private let a = row("a"), b = row("b"), c = row("c")
    private let archiveB = MailChange(.action(.archive), on: [row("b")])
    private var backToB: ReaderCourse.Reader {
        ReaderCourse.Reader(readerRow(b), mailbox: .inbox, labels: [SystemLabel.inbox])
    }

    private func facts(
        reading thread: ThreadSummary.ID?, layout: WindowState.Layout = .viewer, setting: AfterRemoval = .next
    )
        -> ReaderCourse.Facts
    {
        ReaderCourse.Facts(
            reader: thread.map { ReaderCourse.Reader(readerRow($0), mailbox: .inbox, labels: [SystemLabel.inbox]) },
            front: ReaderCourse.Front(rows: [a, b, c], mailbox: .inbox), layout: layout, setting: setting)
    }

    /// The course after the reader opened `b` from an Inbox listing `a`, `b`, `c` and archived it.
    private func archivedB(setting: AfterRemoval = .next) -> ReaderCourse {
        var course = ReaderCourse()
        course.opened(b, from: [a, b, c])
        _ = course.asked(archiveB, facts(reading: b, setting: setting))
        return course
    }

    @Test(arguments: AfterRemoval.allCases)
    func undoRightAfterReadsTheConversationAgain(setting: AfterRemoval) {
        var course = archivedB(setting: setting)
        #expect(course.undone(archiveB) == backToB)
        #expect(course.undone(archiveB) == nil, "once")
    }

    @Test func undoAfterOpeningAnotherAndComingBackBringsBackOnlyTheRow() {
        var course = archivedB()
        // It landed on c; the reader opened a, then c again, so the window shows what the archive left.
        course.opened(a, from: [a, c])
        course.opened(c, from: [a, c])
        #expect(course.undone(archiveB) == nil)
    }

    @Test func undoAfterPickingSeveralSinceBringsBackOnlyTheRow() {
        var course = archivedB()
        course.navigated()
        #expect(course.undone(archiveB) == nil, "Undo doesn't replace a Mac's count of picked rows")
    }

    @Test func undoAfterGoingBackOrToAnotherListBringsBackOnlyTheRow() {
        var course = archivedB(setting: .list)
        course.navigated()
        #expect(course.undone(archiveB) == nil)
    }

    @Test func readingOnWhereTheArchiveLandedKeepsTheWayBack() {
        var course = archivedB()
        let star = MailChange(.action(.star(true)), on: [c])
        // A change is asked only of the conversation on show, which is where the archive landed.
        _ = course.undone(MailChange(.action(.archive), on: [a]))
        #expect(course.undone(archiveB) == backToB, "an Undo for another change leaves this one's way back")
        course = archivedB()
        #expect(course.asked(star, facts(reading: c)) == .stays)
        #expect(course.undone(star) == nil, "the star took nobody anywhere")
        #expect(course.undone(archiveB) == nil, "Undo takes back the star, not the archive")
    }

    @Test func markAsUnreadReturnsOnUndoToo() {
        var course = ReaderCourse()
        let unread = MailChange(.action(.markRead(false)), on: [b])
        #expect(course.asked(unread, facts(reading: b)) == .closes)
        #expect(course.undone(unread) == backToB)
    }

    @Test func aMessageWindowKeepsItsOwnUndo() {
        var course = ReaderCourse()
        #expect(course.asked(archiveB, facts(reading: b, layout: .message)) == .leavesWindow)
        #expect(course.undone(archiveB) == nil)
    }
}
