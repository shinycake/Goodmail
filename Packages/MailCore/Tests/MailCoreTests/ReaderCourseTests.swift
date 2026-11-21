import MailCore
import Testing

/// A window's reader moves only for a change the reader asked of the conversation on show (R6), and then as the
/// setting says (R7, R8).
struct ReaderCourseTests {
    private static func row(_ name: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: name)
    }

    private let a = row("a"), b = row("b"), c = row("c")
    private var rows: [ThreadSummary.ID] { [a, b, c] }

    private func reading(_ thread: ThreadSummary.ID, in mailbox: Mailbox = .inbox) -> ReaderCourse.Reader {
        ReaderCourse.Reader(thread: thread, mailbox: mailbox, labels: [SystemLabel.inbox])
    }

    private func facts(
        reading thread: ThreadSummary.ID?, rows: [ThreadSummary.ID]? = nil, pick: [ThreadSummary.ID] = [],
        state: WindowState = WindowState(), setting: AfterRemoval = .next
    ) -> ReaderCourse.Facts {
        ReaderCourse.Facts(
            reader: thread.map { reading($0) }, rows: rows ?? self.rows, pointerPick: pick, state: state,
            setting: setting)
    }

    @Test func archivingTheOpenConversationReadsTheNextAtOnce() {
        var course = ReaderCourse()
        #expect(course.asked(MailChange(.action(.archive), on: [b]), facts(reading: b)) == .opens(c))
        #expect(course.asked(MailChange(.action(.archive), on: [b]), facts(reading: b, setting: .list)) == .closes)
    }

    @Test func changesToOtherConversationsLeaveTheReaderWhereItIs() {
        var course = ReaderCourse()
        #expect(course.asked(MailChange(.action(.archive), on: [a, c]), facts(reading: b)) == .stays)
        #expect(course.asked(MailChange(.action(.star(true)), on: [b]), facts(reading: b)) == .stays)
    }

    @Test func markAsUnreadGoesBackToTheList() {
        var course = ReaderCourse()
        #expect(course.asked(MailChange(.action(.markRead(false)), on: [b]), facts(reading: b)) == .closes)
    }

    @Test func aMessageWindowLeavesForWhatTakesItsConversation() {
        var course = ReaderCourse()
        let window = facts(reading: b, rows: [], state: WindowState().opening(b, in: .inbox, as: .message))
        #expect(course.asked(MailChange(.action(.trash), on: [b]), window) == .leavesWindow)
        #expect(course.asked(MailChange(.action(.markRead(false)), on: [b]), window) == .leavesWindow)
        #expect(course.asked(MailChange(.action(.star(true)), on: [b]), window) == .stays)
    }

    @Test func aConversationWhoseRowLeftSinceItOpenedGoesOnFromWhereItWas() {
        var course = ReaderCourse()
        course.opened(b, from: rows)
        // Read in an Unread smart mailbox, its row left as it was read.
        #expect(course.asked(MailChange(.snooze, on: [b]), facts(reading: b, rows: [a, c])) == .opens(c))
        course.opened(a, from: [a, c])
        #expect(
            course.asked(MailChange(.snooze, on: [b]), facts(reading: b, rows: [a, c])) == .closes,
            "the trail is the open conversation's, not one opened before it")
    }

    @Test func puttingAwayEveryPointerPickReadsTheRowAfterThem() {
        var course = ReaderCourse()
        let rows = rows + [Self.row("d")]
        let picked = facts(reading: nil, rows: rows, pick: [a, b])
        #expect(course.asked(MailChange(.action(.trash), on: [a, b]), picked) == .opens(c))
        #expect(course.asked(MailChange(.action(.trash), on: [a]), picked) == .stays, "some of them stay")
        #expect(course.asked(MailChange(.action(.star(true)), on: [a, b]), picked) == .stays)
        #expect(
            course.asked(
                MailChange(.action(.trash), on: [a, b]), facts(reading: nil, rows: rows, pick: [a, b], setting: .list))
                == .stays, "nothing is open to close")
        #expect(course.asked(MailChange(.action(.trash), on: [a]), facts(reading: nil)) == .stays)
    }
}
