import MailCore
import Testing

/// A window's reader moves only for a change the reader asked of the conversation on show (R6), and then as the
/// setting says (R7, R8).
struct WindowNavigationPutAwayTests {
    private let a = navigationRow("a"), b = navigationRow("b"), c = navigationRow("c")
    private var rows: [ThreadSummary.ID] { [a.id, b.id, c.id] }

    private func context(_ setting: AfterRemoval = .next) -> WindowNavigation.Context {
        WindowNavigation.Context(arrangement: .stack, afterRemoval: setting)
    }

    private func reader(_ thread: ThreadSummary, in mailbox: Mailbox = .inbox) -> WindowNavigation.Reader {
        WindowNavigation.Reader(thread, mailbox: mailbox, labels: [SystemLabel.inbox])
    }

    /// A viewer that opened `thread` from the Inbox's `rows`, or the three rows.
    private func reading(_ thread: ThreadSummary, from rows: [ThreadSummary.ID]? = nil) -> WindowNavigation {
        var window = WindowNavigation(showing: WindowState())
        window.open(thread, in: .inbox, from: rows ?? self.rows, context())
        return window
    }

    /// `window` after the reader asked `request` of `threads`, with `on` on show and the list listing `rows`.
    private func asking(
        _ window: inout WindowNavigation, _ request: MailChange.Request, of threads: [ThreadSummary],
        on shown: ThreadSummary?, rows: [ThreadSummary.ID]? = nil, pick: [ThreadSummary.ID] = [],
        listedIn front: Mailbox = .inbox, setting: AfterRemoval = .next
    ) -> [WindowNavigation.Effect] {
        window.handle(
            .changed(
                MailChange(request, on: threads.map(\.id)), reader: shown.map { reader($0) },
                front: WindowNavigation.Front(rows: rows ?? self.rows, pointerPick: pick, mailbox: front)),
            in: context(setting))
    }

    @Test func archivingTheOpenConversationReadsTheNextAtOnce() {
        var window = reading(b)
        #expect(asking(&window, .action(.archive), of: [b], on: b) == [])
        #expect(window.state.reading == Reading(c.id, in: .inbox))
        #expect(window.state.stack.count == 3, "the next takes the reader's place (R1)")
        #expect(window.foundRow == nil, "its row is the list's")

        var back = reading(b)
        _ = asking(&back, .action(.archive), of: [b], on: b, setting: .list)
        #expect(back.state.stack == [.mailboxes, .list])
    }

    @Test func theNextIsReadWhereTheListOnShowReadsItsRows() {
        // Opened from an alert in the Inbox, and listed by the search results over it, which read in All Mail.
        var window = reading(b)
        _ = asking(&window, .action(.archive), of: [b], on: b, listedIn: .allMail)
        #expect(window.state.reading == Reading(c.id, in: .allMail))

        var picked = WindowNavigation(showing: WindowState(list: .mailbox(.starred)))
        _ = asking(&picked, .action(.trash), of: [a], on: nil, pick: [a.id], listedIn: .starred)
        #expect(picked.state.reading == Reading(b.id, in: .starred))
    }

    @Test func changesToOtherConversationsLeaveTheReaderWhereItIs() {
        var window = reading(b)
        let before = window.state
        _ = asking(&window, .action(.archive), of: [a, c], on: b)
        _ = asking(&window, .action(.star(true)), of: [b], on: b)
        #expect(window.state == before)
    }

    @Test func markAsUnreadGoesBackToTheList() {
        var window = reading(b)
        _ = asking(&window, .action(.markRead(false)), of: [b], on: b)
        #expect(window.state.reading == nil)
    }

    @Test func aMessageWindowLeavesForWhatTakesItsConversation() {
        for (request, effects) in [
            (MailChange.Request.action(.trash), [WindowNavigation.Effect.leaveWindow]),
            (.action(.markRead(false)), [.leaveWindow]), (.action(.star(true)), []),
        ] {
            var window = WindowNavigation(showing: WindowState(place: .message(Reading(b.id, in: .inbox))))
            #expect(asking(&window, request, of: [b], on: b) == effects)
            #expect(window.state.reading == Reading(b.id, in: .inbox), "it shows its conversation until it goes")
        }
    }

    @Test func aWindowWithNoListGoesBackToNothing() {
        var window = reading(b)
        _ = window.handle(
            .changed(MailChange(.action(.archive), on: [b.id]), reader: reader(b), front: nil), in: context())
        #expect(window.state.reading == nil)
    }

    @Test func aConversationWhoseRowLeftSinceItOpenedGoesOnFromWhereItWas() {
        // Read in an Unread smart mailbox, its row left as it was read.
        var window = reading(b)
        _ = asking(&window, .snooze, of: [b], on: b, rows: [a.id, c.id])
        #expect(window.state.reading == Reading(c.id, in: .inbox))

        var later = reading(a, from: [a.id, c.id])
        _ = asking(&later, .snooze, of: [b], on: b, rows: [a.id, c.id])
        #expect(later.state.reading == nil, "the trail is the open conversation's, not one opened before it")
    }

    @Test func theConversationItGoesOnToGoesOnFromTheRowsItOpenedFrom() {
        var window = reading(a)
        _ = asking(&window, .snooze, of: [a], on: a)
        #expect(window.state.reading == Reading(b.id, in: .inbox))
        // Read in an Unread smart mailbox, b's row left as it was read, and a's with it.
        _ = asking(&window, .snooze, of: [b], on: b, rows: [c.id])
        #expect(window.state.reading == Reading(c.id, in: .inbox))
    }

    @Test func theRowsOfAnotherListAreNeverItsTrail() {
        // Opened from the search results, which listed b; search ended, and the list doesn't list b.
        var window = WindowNavigation(showing: WindowState())
        _ = window.handle(.route(.thread(b.id, in: .allMail)), in: context())
        _ = window.handle(.found(b, rows: rows, searching: true), in: context())
        _ = asking(&window, .snooze, of: [b], on: b, rows: [a.id, c.id])
        #expect(window.state.reading == nil, "the results' rows don't place it in the list")

        var searched = WindowNavigation(showing: WindowState())
        _ = searched.handle(.route(.thread(b.id, in: .allMail)), in: context())
        _ = searched.handle(.found(b, rows: rows, searching: true), in: context())
        let results = WindowNavigation.Front(rows: [a.id, c.id], mailbox: .allMail, searching: true)
        _ = searched.handle(
            .changed(MailChange(.snooze, on: [b.id]), reader: reader(b, in: .allMail), front: results), in: context())
        #expect(searched.state.reading == Reading(c.id, in: .allMail), "the results it was opened from place it")
    }

    @Test func puttingAwayEveryPointerPickReadsTheRowAfterThem() {
        let d = navigationRow("d")
        let rows = rows + [d.id]
        var window = WindowNavigation(showing: WindowState())
        _ = asking(&window, .action(.trash), of: [a, b], on: nil, rows: rows, pick: [a.id, b.id])
        #expect(window.state.reading == Reading(c.id, in: .inbox))

        for (request, threads, setting) in [
            (MailChange.Request.action(.trash), [a], AfterRemoval.next), (.action(.star(true)), [a, b], .next),
            (.action(.trash), [a, b], .list),
        ] {
            var stays = WindowNavigation(showing: WindowState())
            _ = asking(&stays, request, of: threads, on: nil, rows: rows, pick: [a.id, b.id], setting: setting)
            #expect(stays.state == WindowState(), "some stay, nothing is put away, or nothing is open to close")
        }
    }

    @Test func aLabelTakenOffPutsAwayOnlyWhereItIsRead() {
        let label = Mailbox(labelID: "Label_1", accountID: AccountID(rawValue: "a"))
        var window = WindowNavigation(showing: WindowState(list: .mailbox(label)))
        window.open(b, in: label, from: rows, context())
        let labeled = WindowNavigation.Reader(b, mailbox: label, labels: ["Label_1"])
        let front = WindowNavigation.Front(rows: rows, mailbox: label)
        _ = window.handle(
            .changed(
                MailChange(.action(.modifyLabels(add: [], remove: ["Label_2"])), on: [b.id]), reader: labeled,
                front: front),
            in: context())
        #expect(window.state.reading == Reading(b.id, in: label))
        _ = window.handle(
            .changed(
                MailChange(.action(.modifyLabels(add: [], remove: ["Label_1"])), on: [b.id]), reader: labeled,
                front: front),
            in: context())
        #expect(window.state.reading == Reading(c.id, in: label))
    }
}
