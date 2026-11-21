import Foundation
import MailCore
import Testing

struct WindowStateTests {
    private let work = AccountID(rawValue: "work")
    private let home = AccountID(rawValue: "home")

    @Test func aNewWindowShowsTheInboxOnItsPrimaryCategory() {
        #expect(WindowState().list == .mailbox(.inbox, thread: nil))
        #expect(WindowState().category == .primary)
    }

    @Test func aThreadOpensFromAMailboxOrSnoozedButNotScheduled() {
        let thread = ThreadSummary.ID(accountID: work, threadID: "t1")
        var state = WindowState(list: .mailbox(.starred, thread: nil))
        state.setThread(thread)
        #expect(state.list == .mailbox(.starred, thread: thread))
        #expect(state.openThread?.id == thread)
        #expect(state.openThread?.mailbox == .starred)
        state.setThread(nil)
        #expect(state.list == .mailbox(.starred, thread: nil))

        var snoozed = WindowState(list: .snoozed(thread: nil))
        snoozed.setThread(thread)
        #expect(snoozed.openThread?.mailbox == .allMail, "snoozed threads are out of the Inbox")

        var scheduled = WindowState(list: .scheduled)
        scheduled.setThread(thread)
        #expect(scheduled.list == .scheduled)
        #expect(scheduled.openThread == nil)
    }

    @Test func aNewWindowIsUnfiltered() {
        #expect(WindowState().filter == .none)
    }

    @Test func theFilterSurvivesBeingSavedAndAStateSavedWithoutOneIsUnfiltered() throws {
        let filtered = WindowState(filter: .on([.unread, .starred]))
        #expect(try WindowState(saved: filtered.saved()) == filtered)
        var old = try JSONSerialization.jsonObject(with: filtered.saved()) as! [String: Any]
        old["filter"] = nil
        let restored = try WindowState(saved: JSONSerialization.data(withJSONObject: old))
        #expect(restored.filter == .none)
        #expect(restored.list == filtered.list)
    }

    @Test func whatAWindowShowsSurvivesBeingSaved() throws {
        let label = Mailbox(labelID: "Label_7", accountID: work)
        let thread = ThreadSummary.ID(accountID: work, threadID: "t9")
        let states = [
            WindowState(list: .mailbox(label, thread: thread), category: .updates),
            WindowState(list: .mailbox(.allMail, thread: nil)),
            WindowState(list: .snoozed(thread: thread)),
            WindowState(list: .scheduled, category: .social),
        ]
        for state in states {
            #expect(try WindowState(saved: state.saved()) == state)
        }
    }

    @Test func aStateSavedWithAListTitleStillReads() throws {
        let inbox = Mailbox(labelID: SystemLabel.inbox, accountID: work)
        let state = WindowState(list: .mailbox(inbox, thread: nil))
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
        #expect(try WindowState(saved: back.saved()) == WindowState(list: .scheduled))
    }

    @Test func openingAThreadLeavesTheMailboxes() {
        let thread = ThreadSummary.ID(accountID: work, threadID: "t1")
        var state = WindowState(depth: .mailboxes)
        state.setThread(nil)
        #expect(state.depth == .mailboxes)
        state.setThread(thread)
        #expect(state.depth == .list)
    }

    @Test func aGoneAccountKeepsTheWindowAtTheMailboxes() {
        let label = Mailbox(labelID: "Label_7", accountID: home)
        let state = WindowState(list: .mailbox(label, thread: nil), depth: .mailboxes)
        #expect(state.keeping([work]) == WindowState(depth: .mailboxes))
    }

    @Test func savedDataThatIsntAWindowStateIsRefused() {
        #expect(throws: (any Error).self) { try WindowState(saved: Data("not a window".utf8)) }
    }

    @Test func aWindowOnAnAccountThatIsGoneFallsBackToTheInbox() {
        let label = Mailbox(labelID: "Label_7", accountID: home)
        let thread = ThreadSummary.ID(accountID: home, threadID: "t1")
        let state = WindowState(list: .mailbox(label, thread: nil), category: .promotions)
        #expect(state.keeping([work, home]) == state)
        #expect(state.keeping([work]) == WindowState(category: .promotions))

        let unified = WindowState(list: .mailbox(.inbox, thread: thread))
        #expect(
            unified.keeping([work]) == WindowState(list: .mailbox(.inbox, thread: nil)),
            "the unified Inbox stays, without the gone account's thread")
        #expect(WindowState(list: .snoozed(thread: thread)).keeping([work]) == WindowState(list: .snoozed(thread: nil)))
        #expect(WindowState(list: .scheduled).keeping([]) == WindowState(list: .scheduled))
    }

    @Test func aThreadOpenedInANewWindowKeepsTheListItWasOpenedFrom() {
        let label = Mailbox(labelID: "Label_7", accountID: work)
        let thread = ThreadSummary.ID(accountID: work, threadID: "t1")
        let receipts = WindowState(list: .mailbox(label, thread: nil), category: .updates)
        #expect(
            receipts.opening(thread, in: label)
                == WindowState(list: .mailbox(label, thread: thread), category: .updates))
        #expect(
            WindowState(list: .snoozed(thread: nil)).opening(thread, in: .allMail).list == .snoozed(thread: thread))
    }

    @Test func aThreadFoundElsewhereOpensInANewWindowOverItsOwnMailbox() {
        let thread = ThreadSummary.ID(accountID: work, threadID: "t1")
        let other = ThreadSummary.ID(accountID: home, threadID: "t2")
        #expect(
            WindowState(list: .mailbox(.inbox, thread: other)).opening(thread, in: .allMail).list
                == .mailbox(.allMail, thread: thread), "a search result is read in All Mail")
        #expect(
            WindowState(list: .scheduled).opening(thread, in: .inbox).list
                == .mailbox(.inbox, thread: thread))
    }

    @Test func aThreadCanOpenInAWindowOfItsOwnWithTheReaderAlone() {
        let thread = ThreadSummary.ID(accountID: work, threadID: "t1")
        let opened = WindowState(list: .mailbox(.starred, thread: nil)).opening(thread, in: .starred, as: .message)
        #expect(opened.layout == .message)
        #expect(opened.openThread?.id == thread)
        #expect(WindowState().opening(thread, in: .inbox).layout == .viewer, "a new window is a viewer unless asked")
    }

    @Test func aMessageWindowSurvivesBeingSaved() throws {
        let thread = ThreadSummary.ID(accountID: work, threadID: "t1")
        let message = WindowState().opening(thread, in: .inbox, as: .message)
        #expect(try WindowState(saved: message.saved()) == message)
    }

    @Test func aStateSavedBeforeLayoutsReadsAsAViewer() throws {
        let thread = ThreadSummary.ID(accountID: work, threadID: "t1")
        var json = try #require(
            JSONSerialization.jsonObject(with: WindowState(list: .mailbox(.inbox, thread: thread)).saved())
                as? [String: Any])
        json["layout"] = nil
        let state = try WindowState(saved: JSONSerialization.data(withJSONObject: json))
        #expect(state.layout == .viewer)
        #expect(state.openThread?.id == thread)
    }

    /// A message window shows its thread and nothing else, so without one it can only be a viewer.
    @Test func aMessageWindowWithoutItsThreadIsAViewer() throws {
        let thread = ThreadSummary.ID(accountID: home, threadID: "t1")
        var closed = WindowState().opening(thread, in: .inbox, as: .message)
        closed.setThread(nil)
        #expect(closed.layout == .viewer)

        let gone = WindowState().opening(thread, in: .inbox, as: .message).keeping([work])
        #expect(gone.layout == .viewer)
        #expect(gone.openThread == nil)

        #expect(WindowState().laidOut(as: .message).layout == .viewer)
        #expect(
            WindowState(list: .scheduled).opening(thread, in: .inbox, as: .message).laidOut(as: .viewer).layout
                == .viewer)

        var saved = try #require(
            JSONSerialization.jsonObject(with: WindowState().saved()) as? [String: Any])
        saved["layout"] = "message"
        #expect(try WindowState(saved: JSONSerialization.data(withJSONObject: saved)).layout == .viewer)
    }
}
