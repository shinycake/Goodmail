import Foundation
import MailCore
import Testing

struct WindowStateTests {
    private let work = AccountID(rawValue: "work")
    private let home = AccountID(rawValue: "home")
    private var thread: ThreadSummary.ID { ThreadSummary.ID(accountID: work, threadID: "t1") }

    private func reading(
        _ list: WindowState.List, _ reading: Reading, category: InboxCategory = .primary,
        layout: WindowState.Layout = .viewer
    ) -> WindowState {
        var state = WindowState(list: list, category: category)
        state.read(reading)
        return state.laidOut(as: layout)
    }

    private func roundTrip(_ state: WindowState) throws -> WindowState {
        try WindowState(saved: state.saved())
    }

    @Test func aNewWindowShowsTheInboxOnItsPrimaryCategoryReadingNothing() {
        #expect(WindowState().list == .mailbox(.inbox))
        #expect(WindowState().category == .primary)
        #expect(WindowState().reading == nil)
    }

    @Test func aConversationReadsInItsOwnMailboxApartFromTheList() {
        var state = WindowState(list: .mailbox(.inbox))
        state.read(Reading(thread, in: .allMail))
        #expect(state.list == .mailbox(.inbox), "the list stays as it was")
        #expect(state.reading == Reading(thread, in: .allMail))
        state.closeReader()
        #expect(state.reading == nil)
        #expect(state.list == .mailbox(.inbox))
    }

    @Test func aConversationReadsOverScheduled() throws {
        let state = reading(.scheduled, Reading(thread, in: .inbox))
        #expect(state.reading == Reading(thread, in: .inbox))
        #expect(try roundTrip(state) == state)
    }

    @Test func aSearchResultKeepsReadingInAllMailOnceSavedAndRestored() throws {
        let state = reading(.mailbox(.inbox), Reading(thread, in: .allMail), category: .updates)
        let restored = try roundTrip(state)
        #expect(restored.reading?.mailbox == .allMail)
        #expect(restored.list == .mailbox(.inbox))
        #expect(restored.columns == WindowState.Columns(list: .mailbox(.inbox), detail: .reader(state.reading!)))
    }

    @Test func aNewWindowIsUnfiltered() {
        #expect(WindowState().filter == .none)
    }

    @Test func theFilterSurvivesBeingSavedAndAStateSavedWithoutOneIsUnfiltered() throws {
        let filtered = WindowState(filter: .on([.unread, .starred]))
        #expect(try roundTrip(filtered) == filtered)
        var old = try #require(JSONSerialization.jsonObject(with: filtered.saved()) as? [String: Any])
        old["filter"] = nil
        let restored = try WindowState(saved: JSONSerialization.data(withJSONObject: old))
        #expect(restored.filter == .none)
        #expect(restored.list == filtered.list)
    }

    @Test func whatAWindowShowsSurvivesBeingSaved() throws {
        let label = Mailbox(labelID: "Label_7", accountID: work)
        let states = [
            reading(.mailbox(label), Reading(thread, in: label), category: .updates),
            WindowState(list: .mailbox(.allMail)),
            reading(.snoozed, Reading(thread, in: .allMail)),
            reading(.smart(SmartMailbox.ID(rawValue: "vips")), Reading(thread, in: .allMail)),
            reading(.smart(SmartMailbox.ID(rawValue: "vips")), Reading(thread, in: .trash)),
            WindowState(list: .scheduled, category: .social),
            reading(.mailbox(.starred), Reading(thread, in: .starred), layout: .message),
        ]
        for state in states {
            #expect(try roundTrip(state) == state)
        }
    }

    /// A build before `Reading` saved the conversation in the list, read where the list reads.
    @Test(arguments: [
        (OldWindowState.List.mailbox(.starred, thread: nil), WindowState.List.mailbox(.starred), Mailbox?.none),
        (
            .mailbox(.starred, thread: ThreadSummary.ID(accountID: AccountID(rawValue: "work"), threadID: "t1")),
            .mailbox(.starred), .starred
        ),
        (
            .snoozed(thread: ThreadSummary.ID(accountID: AccountID(rawValue: "work"), threadID: "t1")), .snoozed,
            .allMail
        ),
        (.smart(SmartMailbox.ID(rawValue: "unread"), thread: nil), .smart(SmartMailbox.ID(rawValue: "unread")), nil),
        (
            .smart(
                SmartMailbox.ID(rawValue: "unread"),
                thread: ThreadSummary.ID(accountID: AccountID(rawValue: "work"), threadID: "t1")),
            .smart(SmartMailbox.ID(rawValue: "unread")), .allMail
        ),
        (.scheduled, .scheduled, nil),
    ])
    func aStateFromAnOlderBuildReadsAsItDid(old: OldWindowState.List, list: WindowState.List, readIn: Mailbox?)
        throws
    {
        let saved = try JSONEncoder().encode(OldWindowState(list: old, category: .social, filter: .on([.unread])))
        let state = try WindowState(saved: saved)
        #expect(state.list == list)
        #expect(state.category == .social)
        #expect(state.filter == .on([.unread]))
        #expect(state.reading?.mailbox == readIn)
        #expect(state.reading?.thread == readIn.map { _ in thread })
    }

    @Test func anOlderBuildsMessageWindowStaysOne() throws {
        let old = OldWindowState(list: .mailbox(.inbox, thread: thread), layout: .message)
        let state = try WindowState(saved: JSONEncoder().encode(old))
        #expect(state.layout == .message)
        #expect(state.reading == Reading(thread, in: .inbox))
    }

    /// An older build reads what this one saves, ignoring where the conversation reads: it reads it in its list's
    /// mailbox, as it always did.
    @Test func anOlderBuildReadsAStateThisOneSaved() throws {
        let label = Mailbox(labelID: "Label_7", accountID: work)
        let cases: [(WindowState, OldWindowState.List)] = [
            (WindowState(list: .mailbox(label)), .mailbox(label, thread: nil)),
            (reading(.mailbox(.inbox), Reading(thread, in: .allMail)), .mailbox(.inbox, thread: thread)),
            (reading(.snoozed, Reading(thread, in: .allMail)), .snoozed(thread: thread)),
            (
                reading(.smart(SmartMailbox.ID(rawValue: "vips")), Reading(thread, in: .allMail)),
                .smart(SmartMailbox.ID(rawValue: "vips"), thread: thread)
            ),
            (reading(.scheduled, Reading(thread, in: .inbox)), .scheduled),
        ]
        for (state, list) in cases {
            let old = try JSONDecoder().decode(OldWindowState.self, from: state.saved())
            #expect(old == OldWindowState(list: list, category: state.category, filter: state.filter))
        }
        let message = reading(.mailbox(.starred), Reading(thread, in: .starred), layout: .message)
        #expect(try JSONDecoder().decode(OldWindowState.self, from: message.saved()).layout == .message)
    }

    @Test func aStateSavedWithAListTitleStillReads() throws {
        let inbox = Mailbox(labelID: SystemLabel.inbox, accountID: work)
        let state = WindowState(list: .mailbox(inbox))
        var json = try #require(JSONSerialization.jsonObject(with: state.saved()) as? [String: Any])
        var list = try #require(json["list"] as? [String: Any])
        var mailbox = try #require(list["mailbox"] as? [String: Any])
        mailbox["title"] = "INBOX"
        list["mailbox"] = mailbox
        json["list"] = list
        #expect(try WindowState(saved: JSONSerialization.data(withJSONObject: json)) == state)
    }

    @Test func aNarrowWindowBackAtTheMailboxesOpensOnItsListWhenRestored() throws {
        let back = WindowState(list: .scheduled, depth: .mailboxes)
        #expect(try roundTrip(back) == WindowState(list: .scheduled))
    }

    @Test func goingBackToTheMailboxesKeepsTheListAndReadsNothing() {
        let label = Mailbox(labelID: "Label_7", accountID: work)
        var state = reading(.mailbox(label), Reading(thread, in: label), category: .updates, layout: .message)
        state.filter = .on([.unread])
        state.backToMailboxes()
        #expect(state.depth == .mailboxes)
        #expect(state.reading == nil)
        #expect(state.layout == .viewer)
        #expect(state.list == .mailbox(label))
        #expect(state.category == .updates)
        #expect(state.filter == .on([.unread]))
    }

    @Test func readingAConversationLeavesTheMailboxes() {
        var state = WindowState(depth: .mailboxes)
        state.closeReader()
        #expect(state.depth == .mailboxes)
        state.read(Reading(thread, in: .inbox))
        #expect(state.depth == .list)
    }

    @Test func aGoneAccountKeepsTheWindowAtTheMailboxes() {
        let label = Mailbox(labelID: "Label_7", accountID: home)
        let state = WindowState(list: .mailbox(label), depth: .mailboxes)
        #expect(state.keeping([work]) == WindowState(depth: .mailboxes))
    }

    @Test func savedDataThatIsntAWindowStateIsRefused() {
        #expect(throws: (any Error).self) { try WindowState(saved: Data("not a window".utf8)) }
        #expect(throws: (any Error).self) { try WindowState(saved: Data(#"{"list":{},"category":"primary"}"#.utf8)) }
    }

    @Test func aWindowOnAnAccountThatIsGoneFallsBackToTheInbox() {
        let label = Mailbox(labelID: "Label_7", accountID: home)
        let homeThread = ThreadSummary.ID(accountID: home, threadID: "t1")
        let state = WindowState(list: .mailbox(label), category: .promotions)
        #expect(state.keeping([work, home]) == state)
        #expect(state.keeping([work]) == WindowState(category: .promotions))

        let unified = reading(.mailbox(.inbox), Reading(homeThread, in: .inbox))
        #expect(
            unified.keeping([work]) == WindowState(list: .mailbox(.inbox)),
            "the unified Inbox stays, without the gone account's conversation")
        #expect(reading(.snoozed, Reading(homeThread, in: .allMail)).keeping([work]) == WindowState(list: .snoozed))
        #expect(WindowState(list: .scheduled).keeping([]) == WindowState(list: .scheduled))
    }

    @Test func aDeletedLabelOrSmartMailboxFallsBackToTheInbox() {
        let receipts = Mailbox(labelID: "Label_7", accountID: work)
        let vips = SmartMailbox.ID(rawValue: "vips")
        let here = WindowState.OwnLists(labels: [receipts], smartMailboxes: [vips])
        let gone = WindowState.OwnLists(labels: [], smartMailboxes: [])

        let label = reading(.mailbox(receipts), Reading(thread, in: receipts), category: .updates)
        #expect(label.keeping([work], lists: here) == label)
        #expect(
            label.keeping([work], lists: gone)
                == reading(.mailbox(.inbox), Reading(thread, in: .allMail), category: .updates),
            "the conversation reads on in All Mail")

        let smart = reading(.smart(vips), Reading(thread, in: .allMail))
        #expect(smart.keeping([work], lists: here) == smart)
        #expect(smart.keeping([work], lists: gone) == reading(.mailbox(.inbox), Reading(thread, in: .allMail)))

        let accountInbox = WindowState(list: .mailbox(Mailbox(labelID: SystemLabel.inbox, accountID: work)))
        #expect(accountInbox.keeping([work], lists: gone) == accountInbox, "standard mailboxes are never gone")
        #expect(WindowState(list: .snoozed).keeping([work], lists: gone) == WindowState(list: .snoozed))
        #expect(
            WindowState(list: .mailbox(receipts), depth: .mailboxes).keeping([work], lists: gone)
                == WindowState(depth: .mailboxes))
    }

    @Test func aConversationOpenedInANewWindowKeepsTheListItWasOpenedFrom() {
        let label = Mailbox(labelID: "Label_7", accountID: work)
        let receipts = WindowState(list: .mailbox(label), category: .updates)
        #expect(
            receipts.opening(Reading(thread, in: label))
                == reading(.mailbox(label), Reading(thread, in: label), category: .updates))
        #expect(WindowState(list: .snoozed).opening(Reading(thread, in: .allMail)).list == .snoozed)
    }

    @Test func aConversationFoundElsewhereOpensInANewWindowOverItsOwnMailbox() {
        let other = ThreadSummary.ID(accountID: home, threadID: "t2")
        let opened = reading(.mailbox(.inbox), Reading(other, in: .inbox)).opening(Reading(thread, in: .allMail))
        #expect(opened.list == .mailbox(.allMail), "a search result is read in All Mail")
        #expect(opened.reading == Reading(thread, in: .allMail))
        #expect(WindowState(list: .scheduled).opening(Reading(thread, in: .inbox)).list == .mailbox(.inbox))
    }

    @Test func aConversationCanOpenInAWindowOfItsOwnWithTheReaderAlone() {
        let opened = WindowState(list: .mailbox(.starred)).opening(Reading(thread, in: .starred), as: .message)
        #expect(opened.layout == .message)
        #expect(opened.reading?.thread == thread)
        #expect(WindowState().opening(Reading(thread, in: .inbox)).layout == .viewer, "a viewer unless asked")
    }

    @Test func aStateSavedBeforeLayoutsReadsAsAViewer() throws {
        var json = try #require(
            JSONSerialization.jsonObject(with: reading(.mailbox(.inbox), Reading(thread, in: .inbox)).saved())
                as? [String: Any])
        json["layout"] = nil
        let state = try WindowState(saved: JSONSerialization.data(withJSONObject: json))
        #expect(state.layout == .viewer)
        #expect(state.reading?.thread == thread)
    }

    /// A message window shows its conversation and nothing else, so without one it can only be a viewer.
    @Test func aMessageWindowReadingNothingIsAViewer() throws {
        let homeThread = ThreadSummary.ID(accountID: home, threadID: "t1")
        var closed = WindowState().opening(Reading(homeThread, in: .inbox), as: .message)
        closed.closeReader()
        #expect(closed.layout == .viewer)

        let gone = WindowState().opening(Reading(homeThread, in: .inbox), as: .message).keeping([work])
        #expect(gone.layout == .viewer)
        #expect(gone.reading == nil)

        #expect(WindowState().laidOut(as: .message).layout == .viewer)

        var saved = try #require(JSONSerialization.jsonObject(with: WindowState().saved()) as? [String: Any])
        saved["layout"] = "message"
        #expect(try WindowState(saved: JSONSerialization.data(withJSONObject: saved)).layout == .viewer)
    }
}

/// `Mailbox.holding(_:)` names the one standard mailbox a conversation is in, for arrivals from outside the window.
struct MailboxHoldingTests {
    @Test(arguments: [
        ([SystemLabel.inbox, SystemLabel.trash], Mailbox.trash),
        ([SystemLabel.spam, SystemLabel.inbox], .spam),
        ([SystemLabel.draft, SystemLabel.inbox], .drafts),
        ([SystemLabel.inbox, SystemLabel.sent], .inbox),
        ([SystemLabel.sent, "Label_7"], .sent),
        (["Label_7"], .allMail),
    ])
    func theMailboxHoldingLabels(labels: [String], mailbox: Mailbox) {
        #expect(Mailbox.holding(Set(labels)) == mailbox)
    }
}
