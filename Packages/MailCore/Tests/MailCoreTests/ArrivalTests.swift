import Foundation
import MailCore
import Testing

/// A route from outside the window, as a tapped alert, uncovers the window (R3), shows the conversation in a list that
/// holds it (R4), and says when it is gone (R10).
struct ArrivalTests {
    private let stack = WindowNavigation.Context(arrangement: .stack)
    private let columns = WindowNavigation.Context(arrangement: .columns)
    private let accounts = [AccountID(rawValue: "a")]

    // MARK: Uncovering

    @Test func anArrivalUncoversBeforeItLooksUp() {
        var window = WindowNavigation(showing: WindowState())
        let alert = row("b")
        #expect(
            window.handle(.route(.thread(alert.id, in: .inbox), from: .outside), in: stack) == [
                .uncover, .lookUp(alert.id),
            ])
    }

    @Test func theConversationReadAlreadyIsOnlyUncovered() {
        var window = WindowNavigation(showing: WindowState())
        let read = row("b")
        _ = window.handle(.route(.thread(read.id, in: .inbox)), in: stack)
        _ = window.handle(.found(read, rows: [read.id]), in: stack)
        let before = window
        #expect(window.handle(.route(.thread(read.id, in: .inbox), from: .outside), in: stack) == [.uncover], "R2")
        #expect(window == before)
    }

    @Test func aListOrAScreenFromOutsideUncoversToo() {
        var window = WindowNavigation(showing: WindowState())
        #expect(window.handle(.route(.mailbox(.starred), from: .outside), in: columns) == [.uncover, .showList])
        let draft = Draft(accountID: AccountID(rawValue: "a"))
        #expect(
            window.handle(.route(.compose(draft), from: .outside), in: stack) == [.uncover, .present(.compose(draft))])
        #expect(
            window.handle(.route(.settings(.main), from: .outside), in: stack) == [.present(.settings(.main))],
            "Settings comes up over what is up, so an open one isn't dismissed only to show again")
    }

    @Test func aRouteFromInsideUncoversNothing() {
        var window = WindowNavigation(showing: WindowState())
        #expect(window.handle(.route(.mailbox(.starred)), in: stack) == [], "R5")
        #expect(window.handle(.route(.thread(row("b").id, in: .inbox)), in: stack) == [.lookUp(row("b").id)])
    }

    @Test func handoffUncovers() {
        var window = WindowNavigation(showing: WindowState())
        #expect(
            window.handle(.handedOff(WindowState(list: .mailbox(.sent)), accounts: accounts), in: stack) == [
                .uncover
            ])
    }

    // MARK: The list it shows in (R4)

    @Test func theListOnShowStaysWhenItListsTheConversation() {
        let smart = WindowState.List.smart(SmartMailbox.ID(rawValue: "s"))
        let alert = row("b", labels: [SystemLabel.inbox])
        var window = WindowNavigation(showing: WindowState(list: smart))
        arrive(at: alert, in: .inbox, listing: [row("a").id, alert.id], &window)
        #expect(window.state.list == smart, "its rows list it")
        #expect(window.state.reading == Reading(alert.id, in: .allMail), "read as a smart mailbox reads")
    }

    @Test func aMailboxOnShowThatHoldsTheConversationStays() {
        let label = Mailbox(labelID: "Label_1", accountID: AccountID(rawValue: "a"))
        let alert = row("b", labels: [SystemLabel.inbox, "Label_1"])
        var window = WindowNavigation(showing: WindowState(list: .mailbox(label)))
        arrive(at: alert, in: .inbox, listing: [], &window)
        #expect(window.state.list == .mailbox(label), "its labels put it here, though its row isn't loaded")
        #expect(window.state.reading == Reading(alert.id, in: label))
    }

    @Test func anotherListGivesWayToTheRoutesMailbox() {
        let other = Mailbox(labelID: SystemLabel.inbox, accountID: AccountID(rawValue: "work"))
        let alert = row("b", labels: [SystemLabel.inbox])
        var window = WindowNavigation(showing: WindowState(list: .mailbox(other)))
        arrive(at: alert, in: .inbox, listing: [row("a").id], &window)
        #expect(window.state.list == .mailbox(.inbox), "another account's Inbox doesn't hold it")
        #expect(window.state.reading == Reading(alert.id, in: .inbox))
        #expect(
            window.state.stack == [.mailboxes, .list(.mailbox(.inbox)), .reader(Reading(alert.id, in: .inbox))])
    }

    @Test(
        arguments: [
            ([SystemLabel.trash], .trash), ([SystemLabel.spam], .spam), ([], .allMail), ([SystemLabel.sent], .sent),
        ] as [(Set<String>, Mailbox)])
    func oneTheRoutesMailboxNoLongerHoldsShowsWhereItIsNow(labels: Set<String>, holding: Mailbox) {
        let alert = row("b", labels: labels)
        var window = WindowNavigation(showing: WindowState(list: .mailbox(.starred)))
        arrive(at: alert, in: .inbox, listing: [], &window)
        #expect(window.state.list == .mailbox(holding), "archived or trashed since the alert")
        #expect(window.state.reading == Reading(alert.id, in: holding), "so its toolbar is Trash's or Spam's")
    }

    @Test(arguments: [
        ("CATEGORY_PROMOTIONS", InboxCategory.promotions), ("CATEGORY_SOCIAL", .social),
        ("CATEGORY_PERSONAL", .primary),
    ])
    func theInboxShowsTheConversationsCategory(label: String, category: InboxCategory) {
        let alert = row("b", labels: [SystemLabel.inbox, label])
        var window = WindowNavigation(showing: WindowState(category: .updates))
        arrive(at: alert, in: .inbox, listing: [row("a").id], &window)
        #expect(window.state.list == .mailbox(.inbox))
        #expect(window.state.category == category)
        #expect(window.state.reading == Reading(alert.id, in: .inbox))
    }

    @Test func anUnsortedInboxShowsPrimary() {
        let alert = row("b", labels: [SystemLabel.inbox, "CATEGORY_PROMOTIONS"])
        var window = WindowNavigation(showing: WindowState(category: .social))
        let context = WindowNavigation.Context(arrangement: .stack, unsortedInboxes: [alert.id.accountID])
        _ = window.handle(.route(.thread(alert.id, in: .inbox), from: .outside), in: context)
        _ = window.handle(.found(alert, rows: []), in: context)
        #expect(window.state.category == .primary, "its account keeps all of its Inbox in Primary")
    }

    @Test func aCategorySwitchedLeavesNoTrail() {
        let promotion = row("b", labels: [SystemLabel.inbox, "CATEGORY_PROMOTIONS"])
        var window = WindowNavigation(showing: WindowState())
        // As though Primary's rows listed it: they are Primary's still, not the category it shows in.
        arrive(at: promotion, in: .inbox, listing: [row("a").id, promotion.id, row("c").id], &window)
        #expect(window.state.category == .promotions)
        let change = MailChange(.action(.archive), on: [promotion.id])
        let reader = WindowNavigation.Reader(promotion, mailbox: .inbox, labels: promotion.labelIDs)
        let front = WindowNavigation.Front(rows: [], pointerPick: [], mailbox: .inbox)
        _ = window.handle(.changed(change, reader: reader, front: front), in: stack)
        #expect(window.state.reading == nil, "Primary's rows were never Promotions' trail")
    }

    @Test func theRowsOfAListThatStaysAreTheTrail() {
        let a = row("a")
        let alert = row("b")
        let c = row("c")
        var window = WindowNavigation(showing: WindowState())
        arrive(at: alert, in: .inbox, listing: [a.id, alert.id, c.id], &window)
        let change = MailChange(.action(.archive), on: [alert.id])
        let reader = WindowNavigation.Reader(alert, mailbox: .inbox, labels: alert.labelIDs)
        let front = WindowNavigation.Front(rows: [a.id, c.id], pointerPick: [], mailbox: .inbox)
        _ = window.handle(.changed(change, reader: reader, front: front), in: stack)
        #expect(window.state.reading == Reading(c.id, in: .inbox), "the row below, as for one opened from the list")
    }

    @Test func anArrivalAtTheMailboxesShowsTheListAndTheConversation() {
        var window = WindowNavigation(showing: WindowState(place: .mailboxes))
        let alert = row("b")
        arrive(at: alert, in: .inbox, listing: [], &window)
        #expect(
            window.state.stack == [.mailboxes, .list(.mailbox(.inbox)), .reader(Reading(alert.id, in: .inbox))],
            "back from the mailboxes, Back goes to the list")
    }

    @Test func anArrivalReplacesTheConversationRead() {
        let a = row("a")
        let alert = row("b")
        var window = WindowNavigation(showing: WindowState())
        _ = window.handle(.route(.thread(a.id, in: .inbox)), in: stack)
        _ = window.handle(.found(a, rows: [a.id, alert.id]), in: stack)
        arrive(at: alert, in: .inbox, listing: [a.id, alert.id], &window)
        #expect(window.state.stack == [.mailboxes, .list(.mailbox(.inbox)), .reader(Reading(alert.id, in: .inbox))])
        #expect(window.foundRow == alert)
    }

    @Test func anArrivalEndsSearch() {
        let a = row("a")
        let alert = row("b")
        let c = row("c")
        var window = WindowNavigation(showing: WindowState())
        _ = window.handle(.searching(true), in: stack)
        arrive(at: alert, in: .inbox, listing: [a.id, alert.id, c.id], &window)
        let change = MailChange(.action(.archive), on: [alert.id])
        let reader = WindowNavigation.Reader(alert, mailbox: .inbox, labels: alert.labelIDs)
        let front = WindowNavigation.Front(rows: [a.id, c.id], pointerPick: [], mailbox: .inbox)
        _ = window.handle(.changed(change, reader: reader, front: front), in: stack)
        #expect(window.state.reading == Reading(c.id, in: .inbox), "opened from the list's own rows")
    }

    // MARK: Gone (R10)

    @Test func aConversationGoneShowsTheInboxAndSaysSo() {
        let a = row("a")
        let gone = row("gone")
        var window = WindowNavigation(showing: WindowState(list: .mailbox(.starred)))
        _ = window.handle(.route(.thread(a.id, in: .starred)), in: columns)
        _ = window.handle(.found(a, rows: [a.id]), in: columns)
        _ = window.handle(.route(.thread(gone.id, in: .inbox), from: .outside), in: columns)
        #expect(window.handle(.missing(gone.id), in: columns) == [.showList, .say(.conversationGone)])
        #expect(window.state == WindowState(list: .mailbox(.inbox)))
        #expect(window.pending == nil)
    }

    @Test func aConversationMissingForTheWindowsOwnRouteSaysNothing() {
        var window = WindowNavigation(showing: WindowState(list: .mailbox(.starred)))
        _ = window.handle(.route(.thread(row("gone").id, in: .inbox)), in: stack)
        #expect(window.handle(.missing(row("gone").id), in: stack) == [])
        #expect(window.state == WindowState(list: .mailbox(.starred)))
    }

    @Test func aGoneAnswerForAnArrivalMovedOnFromSaysNothing() {
        var window = WindowNavigation(showing: WindowState())
        _ = window.handle(.route(.thread(row("gone").id, in: .inbox), from: .outside), in: stack)
        _ = window.handle(.route(.mailbox(.sent)), in: stack)
        #expect(window.handle(.missing(row("gone").id), in: stack) == [])
        #expect(window.state.list == .mailbox(.sent))
    }

    // MARK: Cold launch

    @Test func aColdLaunchClosesTheRestoredConversationBeforeAnythingIsBuilt() {
        let restored = Reading(row("a").id, in: .inbox)
        let alert = row("b")
        var window = WindowNavigation(showing: WindowState(place: .list(reading: restored)))
        #expect(window.handle(.launched(for: .thread(alert.id, in: .inbox)), in: stack) == [.lookUp(alert.id)])
        #expect(window.state.reading == nil, "no reader is built for the restored one under the new one")
        _ = window.handle(.found(alert, rows: []), in: stack)
        #expect(window.state.stack == [.mailboxes, .list(.mailbox(.inbox)), .reader(Reading(alert.id, in: .inbox))])
    }

    @Test func aColdLaunchForTheRestoredConversationKeepsIt() {
        let restored = Reading(row("a").id, in: .inbox)
        var window = WindowNavigation(showing: WindowState(place: .list(reading: restored)))
        #expect(window.handle(.launched(for: .thread(restored.thread, in: .inbox)), in: stack) == [])
        #expect(window.state.reading == restored)
    }

    @Test func aColdLaunchInARestoredMessageWindowReadsInAViewer() {
        let restored = Reading(row("a").id, in: .inbox)
        let alert = row("b")
        var window = WindowNavigation(showing: WindowState(place: .message(restored)))
        _ = window.handle(.launched(for: .thread(alert.id, in: .inbox)), in: stack)
        _ = window.handle(.found(alert, rows: []), in: stack)
        #expect(window.state.layout == .viewer)
        #expect(window.state.reading == Reading(alert.id, in: .inbox))
    }

    @Test func aColdLaunchForAListShowsIt() {
        let restored = Reading(row("a").id, in: .inbox)
        var window = WindowNavigation(showing: WindowState(place: .list(reading: restored)))
        _ = window.handle(.launched(for: .mailbox(.sent)), in: stack)
        #expect(window.state == WindowState(list: .mailbox(.sent)))
    }

    // MARK: Helpers

    /// Opens `thread` as an arrival from outside asks for it in `mailbox`, with the list on show listing `rows`.
    private func arrive(
        at thread: ThreadSummary, in mailbox: Mailbox, listing rows: [ThreadSummary.ID],
        _ window: inout WindowNavigation
    ) {
        _ = window.handle(.route(.thread(thread.id, in: mailbox), from: .outside), in: stack)
        _ = window.handle(.found(thread, rows: rows), in: stack)
    }

    /// A conversation of the first account named `name`, carrying `labels`.
    private func row(_ name: String, labels: Set<String> = [SystemLabel.inbox]) -> ThreadSummary {
        var row = navigationRow(name)
        row.labelIDs = labels
        return row
    }
}
