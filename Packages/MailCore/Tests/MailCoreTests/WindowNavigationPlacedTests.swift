import MailCore
import Testing

/// The store shows the conversation read out of the mailbox it is read in, by a change from outside the window: another device, an
/// alert action, a rule. The reader closes, so a list beside it never says the mailbox is empty while it still shows
/// one of its conversations; only the reader's own change that left it reading keeps it (R8).
struct WindowNavigationPlacedTests {
    private let a = navigationRow("a"), b = navigationRow("b")
    private var rows: [ThreadSummary.ID] { [a.id, b.id] }

    private func reading(
        _ thread: ThreadSummary, in mailbox: Mailbox = .inbox, _ arrangement: WindowNavigation.Arrangement = .columns
    ) -> WindowNavigation {
        var window = WindowNavigation(showing: WindowState(list: .mailbox(mailbox)))
        window.open(thread, in: mailbox, from: rows, context(arrangement))
        return window
    }

    private func context(_ arrangement: WindowNavigation.Arrangement = .columns) -> WindowNavigation.Context {
        WindowNavigation.Context(arrangement: arrangement)
    }

    @Test(arguments: [WindowNavigation.Arrangement.columns, .stack])
    func theReaderClosesWhenItsConversationLeavesFromOutside(_ arrangement: WindowNavigation.Arrangement) {
        var window = reading(b, arrangement)
        #expect(window.handle(.placed(b.id, inMailbox: false), in: context(arrangement)) == [])
        #expect(window.state.reading == nil)
        #expect(window.state.list == .mailbox(.inbox), "the list stays, with nothing open beside it")
        #expect(
            WindowNavigation.Event.placed(b.id, inMailbox: false).movesByItself, "VoiceOver is told the reader went")
    }

    @Test func anotherConversationLeavingChangesNothing() {
        var window = reading(b)
        let before = window.state
        _ = window.handle(.placed(a.id, inMailbox: false), in: context())
        #expect(window.state == before)
    }

    @Test func aMessageWindowKeepsItsConversation() {
        var window = WindowNavigation(showing: WindowState(place: .message(Reading(b.id, in: .inbox))))
        _ = window.handle(.placed(b.id, inMailbox: false), in: context())
        #expect(window.state.reading == Reading(b.id, in: .inbox), "it shows nothing else, so nothing disagrees")
    }

    /// A viewer reading `b` in Starred whose reader then unstarred it, which R8 keeps reading.
    private func unstarred(_ arrangement: WindowNavigation.Arrangement) -> (WindowNavigation, MailChange, ThreadSummary)
    {
        var starred = navigationRow("b")
        starred.labelIDs = [SystemLabel.starred]
        var window = reading(starred, in: .starred, arrangement)
        let reader = WindowNavigation.Reader(starred, mailbox: .starred, labels: [SystemLabel.starred])
        let front = WindowNavigation.Front(rows: rows, mailbox: .starred)
        let unstar = MailChange(.action(.star(false)), on: [b.id])
        _ = window.handle(.changed(unstar, reader: reader, front: front), in: context(arrangement))
        return (window, unstar, starred)
    }

    @Test(arguments: [WindowNavigation.Arrangement.columns, .stack])
    func theReadersOwnChangeThatKeepsItReadingKeepsIt(_ arrangement: WindowNavigation.Arrangement) {
        var (window, _, starred) = unstarred(arrangement)
        _ = window.handle(.placed(b.id, inMailbox: false), in: context(arrangement))
        #expect(window.state.reading == Reading(b.id, in: .starred), "unstarring in Starred stays (R8)")

        // Opened again, it no longer holds on to that change.
        _ = window.handle(.route(.mailbox(.starred)), in: context(arrangement))
        window.open(starred, in: .starred, from: rows, context(arrangement))
        _ = window.handle(.placed(b.id, inMailbox: false), in: context(arrangement))
        #expect(window.state.reading == nil)
    }

    @Test func undoingThatChangeLetsItGoAgain() {
        var (window, unstar, _) = unstarred(.columns)
        _ = window.handle(.undone(unstar, rows: rows), in: context())
        #expect(window.state.reading == Reading(b.id, in: .starred), "starred again, it is still read")
        _ = window.handle(.placed(b.id, inMailbox: false), in: context())
        #expect(window.state.reading == nil, "unstarred on another device afterwards, it closes")
    }

    @Test func backInItsMailboxItIsNoLongerKept() {
        var (window, _, _) = unstarred(.columns)
        _ = window.handle(.placed(b.id, inMailbox: true), in: context())
        #expect(window.state.reading == Reading(b.id, in: .starred), "starred again")
        _ = window.handle(.placed(b.id, inMailbox: false), in: context())
        #expect(window.state.reading == nil, "unstarred on another device afterwards, it closes")
    }

    @Test func inItsMailboxItStays() {
        var window = reading(b)
        let before = window.state
        _ = window.handle(.placed(b.id, inMailbox: true), in: context())
        #expect(window.state == before)
    }

    @Test func aChangeThatKeepsItWhereItIsReadDoesNotHoldItThere() {
        var window = reading(b)
        let reader = WindowNavigation.Reader(b, mailbox: .inbox, labels: [SystemLabel.inbox])
        let front = WindowNavigation.Front(rows: rows, mailbox: .inbox)
        _ = window.handle(
            .changed(MailChange(.action(.star(true)), on: [b.id]), reader: reader, front: front), in: context())
        _ = window.handle(.placed(b.id, inMailbox: false), in: context())
        #expect(window.state.reading == nil, "starring in the Inbox leaves it there, so archiving elsewhere closes it")
    }
}
