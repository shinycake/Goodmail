import MailCore
import Testing

/// Next and Previous Conversation read the row below or above the one read, in the list it was opened from, in every
/// arrangement, and stop at the ends.
struct WindowNavigationStepTests {
    private let a = navigationRow("a"), b = navigationRow("b"), c = navigationRow("c"), d = navigationRow("d")
    private var rows: [ThreadSummary.ID] { [a.id, b.id, c.id] }

    private func front(_ rows: [ThreadSummary.ID]? = nil, pick: [ThreadSummary.ID] = [], in mailbox: Mailbox = .inbox)
        -> WindowNavigation.Front
    {
        WindowNavigation.Front(rows: rows ?? self.rows, pointerPick: pick, mailbox: mailbox)
    }

    /// A viewer laid out as `arrangement` that opened `thread` from the Inbox's rows.
    private func reading(_ thread: ThreadSummary, _ arrangement: WindowNavigation.Arrangement = .stack)
        -> WindowNavigation
    {
        var window = WindowNavigation(showing: WindowState())
        window.open(thread, in: .inbox, from: rows, WindowNavigation.Context(arrangement: arrangement))
        return window
    }

    private func step(
        _ window: inout WindowNavigation, _ step: WindowNavigation.Step, through front: WindowNavigation.Front? = nil,
        _ arrangement: WindowNavigation.Arrangement = .stack
    ) -> [WindowNavigation.Effect] {
        window.handle(.step(step, front: front ?? self.front()), in: WindowNavigation.Context(arrangement: arrangement))
    }

    @Test(arguments: [WindowNavigation.Arrangement.stack, .columns])
    func nextIsTheRowBelowAndPreviousTheRowAbove(_ arrangement: WindowNavigation.Arrangement) {
        var window = reading(b, arrangement)
        #expect(step(&window, .next, arrangement) == [])
        #expect(window.state.reading == Reading(c.id, in: .inbox))
        _ = step(&window, .previous, arrangement)
        _ = step(&window, .previous, arrangement)
        #expect(window.state.reading == Reading(a.id, in: .inbox))
        #expect(window.state.stack.count == 3, "each takes the reader's place (R1)")
    }

    @Test func theEndsGoNowhere() {
        let first = reading(a)
        #expect(first.conversation(.previous, in: front()) == nil)
        #expect(first.conversation(.next, in: front()) == b.id)
        var last = reading(c)
        #expect(last.conversation(.next, in: front()) == nil)
        let before = last.state
        _ = step(&last, .next)
        #expect(last.state == before)
    }

    @Test func withNothingReadNextReadsTheFirstRow() {
        let window = WindowNavigation(showing: WindowState())
        #expect(window.conversation(.next, in: front()) == a.id)
        #expect(window.conversation(.previous, in: front()) == nil)
        #expect(window.conversation(.next, in: front([])) == nil, "an empty list")
    }

    @Test func aConversationWhoseRowLeftStepsFromWhereItWas() {
        // b was read, then left the list, as a read conversation leaves the Unread filter.
        let window = reading(b)
        let left = front([a.id, c.id])
        #expect(window.conversation(.next, in: left) == c.id)
        #expect(window.conversation(.previous, in: left) == a.id)
        // And the rows beyond it that left too are passed over.
        #expect(window.conversation(.next, in: front([a.id, d.id])) == nil, "c left, and d was never beside it")
        #expect(window.conversation(.previous, in: front([c.id])) == nil)
    }

    @Test func aConversationTheListNeverHeldHasNoNeighbors() {
        var window = WindowNavigation(showing: WindowState())
        window.open(d, in: .inbox, from: [], WindowNavigation.Context(arrangement: .stack))
        #expect(window.conversation(.next, in: front()) == nil)
        #expect(window.conversation(.previous, in: front()) == nil)
    }

    @Test func itReadsWhereTheListOnShowReadsItsRows() {
        var window = reading(b)
        _ = step(&window, .next, through: front(in: .allMail))
        #expect(window.state.reading == Reading(c.id, in: .allMail), "search results read in All Mail")
    }

    @Test func severalPickedOrAMessageWindowStepNowhere() {
        let picked = WindowNavigation(showing: WindowState())
        #expect(picked.conversation(.next, in: front(pick: [a.id, b.id])) == nil)
        let message = WindowNavigation(showing: WindowState(place: .message(Reading(b.id, in: .inbox))))
        #expect(message.conversation(.next, in: front()) == nil)
        #expect(reading(b).conversation(.next, in: nil) == nil, "no list on show")
    }

    @Test func steppingEndsUndosWayBack() {
        var window = reading(b)
        let archive = MailChange(.action(.archive), on: [b.id])
        let context = WindowNavigation.Context(arrangement: .stack)
        _ = window.handle(
            .changed(
                archive, reader: WindowNavigation.Reader(b, mailbox: .inbox, labels: [SystemLabel.inbox]),
                front: front()), in: context)
        #expect(window.state.reading?.thread == c.id)
        _ = step(&window, .previous, through: front([a.id, c.id]))
        #expect(window.state.reading?.thread == a.id)
        _ = window.handle(.undone(archive, rows: rows), in: context)
        #expect(window.state.reading?.thread == a.id, "Undo brings back only the row once the reader moved on (R9)")
    }

    @Test func aStepIsAnnounced() {
        #expect(WindowNavigation.Event.step(.next, front: nil).movesByItself)
    }
}
