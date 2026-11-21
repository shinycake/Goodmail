import Foundation
import MailCore
import Testing

/// Every way a window moves but its course's own landing ends the way back Undo would take (R9), so no caller can
/// forget to.
struct WindowCourseTests {
    private static func row(_ name: String) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: name), subject: name, snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: .distantPast, isUnread: false,
            messageCount: 1, labelIDs: [SystemLabel.inbox])
    }

    private let a = row("a"), b = row("b"), c = row("c")
    private var rows: [ThreadSummary.ID] { [a.id, b.id, c.id] }
    private var archiveB: MailChange { MailChange(.action(.archive), on: [b.id]) }

    /// A window that opened `b` from the Inbox, archived it and landed on `c`.
    private func archivedB() -> WindowCourse {
        var window = WindowCourse(showing: WindowState())
        window.opened(Reading(b.id, in: .inbox), from: rows)
        let facts = ReaderCourse.Facts(
            reader: ReaderCourse.Reader(b, mailbox: .inbox, labels: [SystemLabel.inbox]),
            front: ReaderCourse.Front(rows: rows, mailbox: .inbox), layout: .viewer, setting: .next)
        #expect(window.asked(archiveB, facts) == .opens(Reading(c.id, in: .inbox)))
        window.landed(on: Reading(c.id, in: .inbox))
        return window
    }

    @Test func landingKeepsTheWayBack() {
        var window = archivedB()
        #expect(window.shown.reading == Reading(c.id, in: .inbox))
        let back = window.undone(archiveB, rows: rows)
        #expect(back?.summary == b, "the row as the reader read it, so nothing is read from the store")
        #expect(back?.mailbox == .inbox)
        #expect(window.shown.reading == Reading(c.id, in: .inbox), "the window shows it once it records the landing")
    }

    @Test func landingOnTheListClosesTheReaderAndKeepsTheWayBack() {
        var window = archivedB()
        window.landedOnList()
        #expect(window.shown.reading == nil)
        #expect(window.undone(archiveB, rows: rows)?.summary == b)
    }

    @Test func anyOtherMoveEndsIt() {
        let moves: [(inout WindowState) -> Void] = [
            { $0 = WindowState(list: .mailbox(.starred)) },
            { $0.closeReader() },
            { $0.filter = .on([.unread]) },
            { _ in },
        ]
        for move in moves {
            var window = archivedB()
            window.move(move)
            #expect(window.undone(archiveB, rows: rows) == nil)
        }
    }

    @Test func openingAnotherEndsIt() {
        var window = archivedB()
        window.opened(Reading(a.id, in: .allMail), from: rows)
        #expect(window.shown.reading == Reading(a.id, in: .allMail), "read where it was opened, as from search")
        #expect(window.undone(archiveB, rows: rows) == nil)
    }
}
