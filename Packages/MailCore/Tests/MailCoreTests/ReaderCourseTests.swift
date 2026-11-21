import Foundation
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
        ReaderCourse.Reader(readerRow(thread), mailbox: mailbox, labels: [SystemLabel.inbox])
    }

    private func facts(
        reading thread: ThreadSummary.ID?, in mailbox: Mailbox = .inbox, rows: [ThreadSummary.ID]? = nil,
        pick: [ThreadSummary.ID] = [], listedIn front: Mailbox = .inbox, layout: WindowState.Layout = .viewer,
        setting: AfterRemoval = .next
    ) -> ReaderCourse.Facts {
        ReaderCourse.Facts(
            reader: thread.map { reading($0, in: mailbox) },
            front: ReaderCourse.Front(rows: rows ?? self.rows, pointerPick: pick, mailbox: front), layout: layout,
            setting: setting)
    }

    @Test func archivingTheOpenConversationReadsTheNextAtOnce() {
        var course = ReaderCourse()
        #expect(
            course.asked(MailChange(.action(.archive), on: [b]), facts(reading: b))
                == .opens(ReaderCourse.Opening(c, in: .inbox)))
        #expect(course.asked(MailChange(.action(.archive), on: [b]), facts(reading: b, setting: .list)) == .closes)
    }

    @Test func theNextIsReadWhereTheListOnShowReadsItsRows() {
        var course = ReaderCourse()
        // Opened from an alert in the Inbox, and listed by the search results over it, which read in All Mail.
        let fromSearch = facts(reading: b, in: .inbox, listedIn: .allMail)
        #expect(
            course.asked(MailChange(.action(.archive), on: [b]), fromSearch)
                == .opens(ReaderCourse.Opening(c, in: .allMail)))
        let picked = facts(reading: nil, pick: [a], listedIn: .starred)
        #expect(
            course.asked(MailChange(.action(.trash), on: [a]), picked) == .opens(ReaderCourse.Opening(b, in: .starred)))
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
        let window = ReaderCourse.Facts(reader: reading(b), front: nil, layout: .message, setting: .next)
        #expect(course.asked(MailChange(.action(.trash), on: [b]), window) == .leavesWindow)
        #expect(course.asked(MailChange(.action(.markRead(false)), on: [b]), window) == .leavesWindow)
        #expect(course.asked(MailChange(.action(.star(true)), on: [b]), window) == .stays)
    }

    @Test func aWindowWithNoListGoesBackToNothing() {
        var course = ReaderCourse()
        let alone = ReaderCourse.Facts(reader: reading(b), front: nil, layout: .viewer, setting: .next)
        #expect(course.asked(MailChange(.action(.archive), on: [b]), alone) == .closes)
    }

    @Test func aConversationWhoseRowLeftSinceItOpenedGoesOnFromWhereItWas() {
        var course = ReaderCourse()
        course.opened(b, from: rows)
        // Read in an Unread smart mailbox, its row left as it was read.
        #expect(
            course.asked(MailChange(.snooze, on: [b]), facts(reading: b, rows: [a, c]))
                == .opens(ReaderCourse.Opening(c, in: .inbox)))
        course.opened(a, from: [a, c])
        #expect(
            course.asked(MailChange(.snooze, on: [b]), facts(reading: b, rows: [a, c])) == .closes,
            "the trail is the open conversation's, not one opened before it")
    }

    @Test func theConversationItOpensGoesOnFromTheRowsItOpenedFrom() {
        var course = ReaderCourse()
        course.opened(a, from: rows)
        #expect(
            course.asked(MailChange(.snooze, on: [a]), facts(reading: a)) == .opens(ReaderCourse.Opening(b, in: .inbox))
        )
        // Read in an Unread smart mailbox, b's row left as it was read, and a's with it.
        #expect(
            course.asked(MailChange(.snooze, on: [b]), facts(reading: b, rows: [c]))
                == .opens(ReaderCourse.Opening(c, in: .inbox)))
    }

    @Test func puttingAwayEveryPointerPickReadsTheRowAfterThem() {
        var course = ReaderCourse()
        let rows = rows + [Self.row("d")]
        let picked = facts(reading: nil, rows: rows, pick: [a, b])
        #expect(
            course.asked(MailChange(.action(.trash), on: [a, b]), picked)
                == .opens(ReaderCourse.Opening(c, in: .inbox)))
        #expect(course.asked(MailChange(.action(.trash), on: [a]), picked) == .stays, "some of them stay")
        #expect(course.asked(MailChange(.action(.star(true)), on: [a, b]), picked) == .stays)
        #expect(
            course.asked(
                MailChange(.action(.trash), on: [a, b]), facts(reading: nil, rows: rows, pick: [a, b], setting: .list))
                == .stays, "nothing is open to close")
        #expect(course.asked(MailChange(.action(.trash), on: [a]), facts(reading: nil)) == .stays)
    }
}

/// A row of `id`, as a reader opens it.
func readerRow(_ id: ThreadSummary.ID) -> ThreadSummary {
    ThreadSummary(
        id: id, subject: id.threadID, snippet: "", sender: Contact(name: nil, address: "x@example.com"),
        date: .distantPast, isUnread: false, messageCount: 1, labelIDs: [SystemLabel.inbox])
}
