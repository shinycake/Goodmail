import Foundation
import MailCore
import Testing

/// Routes asked from inside a window move it by one transition, and only as far as they ask (R1, R2, R5).
struct WindowNavigationTests {
    private let a = navigationRow("a"), b = navigationRow("b"), c = navigationRow("c")
    private var rows: [ThreadSummary.ID] { [a.id, b.id, c.id] }
    private let stack = WindowNavigation.Context(arrangement: .stack)
    private let columns = WindowNavigation.Context(arrangement: .columns)

    /// A viewer on the Inbox that opened `thread` from its rows.
    private func reading(_ thread: ThreadSummary, in context: WindowNavigation.Context) -> WindowNavigation {
        var window = WindowNavigation(showing: WindowState())
        window.open(thread, in: .inbox, from: rows, context)
        return window
    }

    // MARK: Conversations

    @Test(arguments: [WindowNavigation.Arrangement.stack, .columns])
    func aConversationIsLookedUpThenRead(arrangement: WindowNavigation.Arrangement) {
        let context = WindowNavigation.Context(arrangement: arrangement)
        var window = WindowNavigation(showing: WindowState())
        #expect(window.handle(.route(.thread(b.id, in: .allMail)), in: context) == [.lookUp(b.id, in: .allMail)])
        #expect(window.state.reading == nil, "nothing changes until it is found")
        #expect(window.handle(.found(b, in: .allMail, rows: rows), in: context) == [])
        #expect(window.state.reading == Reading(b.id, in: .allMail), "read where the route reads it, as from search")
        #expect(window.foundRow == b, "its reader is made from the row found")
    }

    @Test func aConversationTakesThePlaceOfTheOneRead() {
        var window = reading(a, in: stack)
        window.open(c, in: .inbox, from: rows, stack)
        #expect(window.state.reading == Reading(c.id, in: .inbox))
        #expect(
            window.state.stack == [.mailboxes, .list(.mailbox(.inbox)), .reader(Reading(c.id, in: .inbox))],
            "one reader, so Back goes to the list (R1)")
    }

    @Test func theConversationReadAlreadyChangesNothing() {
        var window = reading(b, in: stack)
        let before = window
        #expect(window.handle(.route(.thread(b.id, in: .inbox)), in: stack) == [], "no lookup, no new reader (R2)")
        #expect(window.handle(.route(.thread(b.id, in: .allMail)), in: columns) == [])
        #expect(window.handle(.found(b, in: .allMail, rows: []), in: stack) == [], "found again meanwhile")
        #expect(window == before)
    }

    @Test func aConversationMissingChangesNothing() {
        var window = reading(a, in: stack)
        let before = window
        #expect(window.handle(.missing(c.id), in: stack) == [])
        #expect(window == before)
    }

    @Test func theConversationReadMissingCloses() {
        var window = reading(a, in: stack)
        _ = window.handle(.missing(a.id), in: stack)
        #expect(window.state == WindowState())
        var message = WindowNavigation(showing: WindowState(place: .message(Reading(a.id, in: .inbox))))
        _ = message.handle(.missing(a.id), in: stack)
        #expect(message.state == WindowState(), "a message window becomes a viewer")
    }

    @Test func aMessageWindowReadsOnlyItsOwn() {
        var window = WindowNavigation(showing: WindowState(place: .message(Reading(a.id, in: .inbox))))
        let before = window
        #expect(window.handle(.route(.thread(b.id, in: .inbox)), in: stack) == [])
        #expect(window.handle(.found(b, in: .inbox, rows: rows), in: stack) == [])
        #expect(window.handle(.route(.mailbox(.starred)), in: stack) == [])
        #expect(window.handle(.route(.search(SearchQuery(terms: []))), in: stack) == [])
        #expect(window.handle(.back(to: .list), in: stack) == [])
        #expect(window == before)
    }

    @Test func aNarrowWindowAtTheMailboxesOpensTheListUnderTheConversation() {
        var window = WindowNavigation(showing: WindowState(place: .mailboxes))
        window.open(a, in: .inbox, from: rows, stack)
        #expect(window.state.stack == [.mailboxes, .list(.mailbox(.inbox)), .reader(Reading(a.id, in: .inbox))])
    }

    // MARK: Lists

    @Test func aMailboxClosesTheReaderInAStack() {
        var window = reading(b, in: stack)
        #expect(window.handle(.route(.mailbox(.starred)), in: stack) == [])
        #expect(window.state.stack == [.mailboxes, .list(.mailbox(.starred))])
    }

    @Test func aMailboxKeepsTheReaderBesideItInColumns() {
        var window = reading(b, in: columns)
        #expect(window.handle(.route(.mailbox(.starred)), in: columns) == [.showList])
        #expect(window.state.columns == .init(list: .mailbox(.starred), detail: .reader(Reading(b.id, in: .inbox))))
    }

    @Test func theListShownAlreadyClosesTheReaderInAStack() {
        var window = reading(b, in: stack)
        _ = window.handle(.route(.mailbox(.inbox)), in: stack)
        #expect(window.state.stack == [.mailboxes, .list(.mailbox(.inbox))], "the same list, without the reader")
    }

    @Test func everyListKeepsTheCategoryAndFilter() {
        var window = WindowNavigation(
            showing: WindowState(category: .promotions, filter: .on([.unread]), place: .mailboxes))
        for (route, list) in [
            (Route.scheduled, WindowState.List.scheduled), (.snoozed, .snoozed),
            (.smartMailbox(SmartMailbox.ID(rawValue: "s")), .smart(SmartMailbox.ID(rawValue: "s"))),
            (.mailbox(.allMail), .mailbox(.allMail)),
        ] {
            _ = window.handle(.route(route), in: stack)
            #expect(window.state == WindowState(list: list, category: .promotions, filter: .on([.unread])))
        }
    }

    // MARK: Search

    @Test func searchClosesTheReaderInAStackOverTheMailboxList() {
        var window = reading(b, in: stack)
        let query = SearchQuery(terms: [.unread])
        #expect(window.handle(.route(.search(query)), in: stack) == [.beginSearch(query)])
        #expect(window.state.stack == [.mailboxes, .list(.mailbox(.inbox))])
    }

    @Test func searchKeepsTheReaderBesideTheMailboxListInColumns() {
        var window = reading(b, in: columns)
        let query = SearchQuery(terms: [])
        #expect(window.handle(.route(.search(query)), in: columns) == [.showList, .beginSearch(query)])
        #expect(window.state.reading == Reading(b.id, in: .inbox))
    }

    @Test(arguments: [WindowNavigation.Arrangement.stack, .columns])
    func searchFromAnotherListGoesToTheInbox(arrangement: WindowNavigation.Arrangement) {
        let context = WindowNavigation.Context(arrangement: arrangement)
        var window = WindowNavigation(
            showing: WindowState(
                list: .snoozed, category: .social, place: .list(reading: Reading(a.id, in: .allMail))))
        _ = window.handle(.route(.search(SearchQuery(terms: []))), in: context)
        #expect(window.state == WindowState(list: .mailbox(.inbox), category: .social))
    }

    @Test func searchFromTheMailboxesOpensTheList() {
        var window = WindowNavigation(showing: WindowState(list: .mailbox(.sent), place: .mailboxes))
        _ = window.handle(.route(.search(SearchQuery(terms: []))), in: stack)
        #expect(window.state.stack == [.mailboxes, .list(.mailbox(.sent))])
    }

    // MARK: Back

    @Test func backFromTheReaderGoesToTheList() {
        var window = reading(b, in: stack)
        #expect(window.handle(.back(to: .list), in: stack) == [])
        #expect(window.state.stack == [.mailboxes, .list(.mailbox(.inbox))])
        #expect(window.foundRow == nil)
    }

    @Test func backToTheMailboxesKeepsTheListForAWiderWindow() {
        var window = WindowNavigation(showing: WindowState(list: .mailbox(.starred)))
        _ = window.handle(.back(to: .mailboxes), in: stack)
        #expect(window.state.stack == [.mailboxes])
        #expect(window.state.columns.list == .mailbox(.starred))
    }

    // MARK: Picked rows

    @Test func aPickedCountClosesTheReaderBesideTheList() {
        var window = reading(b, in: columns)
        #expect(window.handle(.route(.selection(count: 3)), in: columns) == [.showPicked(3)])
        #expect(window.state.columns.detail == .nothing)
    }

    @Test func aNarrowWindowShowsItsOwnPick() {
        var window = reading(b, in: stack)
        let before = window
        #expect(window.handle(.route(.selection(count: 3)), in: stack) == [])
        #expect(window == before)
    }

    // MARK: Screens presented

    @Test(arguments: [
        Route.compose(Draft(accountID: AccountID(rawValue: "a"))), .changeLabels([]), .move([], from: .inbox),
        .settings(.main), .newSmartMailbox(SearchQuery(terms: [])), .signInAgain(AccountID(rawValue: "a")),
        .newWindow(navigationRow("c").id, in: .inbox), .draft(navigationRow("c").id),
    ])
    func aScreenPresentedMovesNothing(route: Route) {
        var window = reading(b, in: stack)
        let before = window
        #expect(window.handle(.route(route), in: stack) == [.present(route)])
        #expect(window == before)
    }

    // MARK: Accounts, lists and Handoff

    @Test func anAccountRemovedClosesItsConversationAndList() {
        let other = Mailbox(labelID: SystemLabel.inbox, accountID: AccountID(rawValue: "b"))
        var window = WindowNavigation(
            showing: WindowState(list: .mailbox(other), place: .list(reading: Reading(a.id, in: .inbox))))
        _ = window.handle(.accounts([AccountID(rawValue: "b")]), in: columns)
        #expect(window.state == WindowState(list: .mailbox(other)))
    }

    @Test func aDeletedLabelGivesWayToTheInbox() {
        let label = Mailbox(labelID: "Label_1", accountID: AccountID(rawValue: "a"))
        var window = WindowNavigation(showing: WindowState(list: .mailbox(label)))
        let none = WindowState.OwnLists(labels: [], smartMailboxes: [])
        _ = window.handle(.lists(none, accounts: [AccountID(rawValue: "a")]), in: columns)
        #expect(window.state.list == .mailbox(.inbox))
    }

    @Test func aMessageWindowKeepsReadingWhereItWasOpened() {
        let label = Mailbox(labelID: "Label_1", accountID: AccountID(rawValue: "a"))
        let shown = WindowState(list: .mailbox(label), place: .message(Reading(a.id, in: label)))
        var window = WindowNavigation(showing: shown)
        _ = window.handle(
            .lists(.init(labels: [], smartMailboxes: []), accounts: [AccountID(rawValue: "a")]), in: stack)
        #expect(window.state == shown)
    }

    @Test func aHandOffIsLaidOutAsTheWindowIs() {
        let handed = WindowState(list: .mailbox(.starred), place: .message(Reading(a.id, in: .starred)))
        var viewer = reading(b, in: columns)
        _ = viewer.handle(.handedOff(handed, accounts: [AccountID(rawValue: "a")]), in: columns)
        #expect(viewer.state == handed.asViewer)
        #expect(viewer.foundRow == nil, "the screens find its row")

        var message = WindowNavigation(showing: WindowState(place: .message(Reading(b.id, in: .inbox))))
        _ = message.handle(.handedOff(handed.asViewer, accounts: [AccountID(rawValue: "a")]), in: stack)
        #expect(message.state == handed)
        _ = message.handle(.handedOff(WindowState(), accounts: [AccountID(rawValue: "a")]), in: stack)
        #expect(message.state == WindowState(), "nothing read makes it a viewer")
    }

    @Test func aHandOffWaitsForAListNotSyncedYet() {
        let label = Mailbox(labelID: "Label_9", accountID: AccountID(rawValue: "a"))
        var window = WindowNavigation(showing: WindowState())
        _ = window.handle(
            .handedOff(WindowState(list: .mailbox(label)), accounts: [AccountID(rawValue: "a")]), in: stack)
        let none = WindowState.OwnLists(labels: [], smartMailboxes: [])
        _ = window.handle(.lists(none, accounts: [AccountID(rawValue: "a")]), in: stack)
        #expect(window.state.list == .mailbox(label), "it may come with the next sync")
        let other = WindowState.OwnLists(labels: [], smartMailboxes: [SmartMailbox.ID(rawValue: "s")])
        _ = window.handle(.lists(other, accounts: [AccountID(rawValue: "a")]), in: stack)
        #expect(window.state.list == .mailbox(.inbox), "still missing once the lists changed")
    }

    @Test func theCategoryAndFilterChangeAlone() {
        var window = reading(b, in: stack)
        _ = window.handle(.category(.updates), in: stack)
        _ = window.handle(.filter(.on([.unread])), in: stack)
        #expect(
            window.state
                == WindowState(
                    category: .updates, filter: .on([.unread]), place: .list(reading: Reading(b.id, in: .inbox))))
    }
}

extension WindowNavigation {
    /// Opens `thread` as a route to it does once it is found.
    mutating func open(_ thread: ThreadSummary, in mailbox: Mailbox, from rows: [ThreadSummary.ID], _ context: Context)
    {
        _ = handle(.route(.thread(thread.id, in: mailbox)), in: context)
        _ = handle(.found(thread, in: mailbox, rows: rows), in: context)
    }
}

/// A row of the first account's Inbox named `name`, as a reader opens it.
func navigationRow(_ name: String) -> ThreadSummary {
    ThreadSummary(
        id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: name), subject: name, snippet: "",
        sender: Contact(name: nil, address: "x@example.com"), date: .distantPast, isUnread: false, messageCount: 1,
        labelIDs: [SystemLabel.inbox])
}
