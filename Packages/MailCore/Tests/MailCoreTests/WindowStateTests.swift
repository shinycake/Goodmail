import Foundation
import MailCore
import Testing

struct WindowStateTests {
    private let work = AccountID(rawValue: "work")
    private let home = AccountID(rawValue: "home")

    @Test func aNewWindowShowsTheInboxOnItsPrimaryCategory() {
        #expect(WindowState().list == .mailbox(.inbox, title: nil, thread: nil))
        #expect(WindowState().category == .primary)
    }

    @Test func aThreadOpensFromAMailboxOrSnoozedButNotScheduled() {
        let thread = ThreadSummary.ID(accountID: work, threadID: "t1")
        var state = WindowState(list: .mailbox(.starred, title: nil, thread: nil))
        state.setThread(thread)
        #expect(state.list == .mailbox(.starred, title: nil, thread: thread))
        #expect(state.openThread?.id == thread)
        #expect(state.openThread?.mailbox == .starred)
        state.setThread(nil)
        #expect(state.list == .mailbox(.starred, title: nil, thread: nil))

        var snoozed = WindowState(list: .snoozed(thread: nil))
        snoozed.setThread(thread)
        #expect(snoozed.openThread?.mailbox == .allMail, "snoozed threads are out of the Inbox")

        var scheduled = WindowState(list: .scheduled)
        scheduled.setThread(thread)
        #expect(scheduled.list == .scheduled)
        #expect(scheduled.openThread == nil)
    }

    @Test func whatAWindowShowsSurvivesBeingSaved() throws {
        let label = Mailbox(labelID: "Label_7", accountID: work)
        let thread = ThreadSummary.ID(accountID: work, threadID: "t9")
        let states = [
            WindowState(list: .mailbox(label, title: "Receipts", thread: thread), category: .updates),
            WindowState(list: .mailbox(.allMail, title: nil, thread: nil)),
            WindowState(list: .snoozed(thread: thread)),
            WindowState(list: .scheduled, category: .social),
        ]
        for state in states {
            #expect(try WindowState(saved: state.saved()) == state)
        }
    }

    @Test func savedDataThatIsntAWindowStateIsRefused() {
        #expect(throws: (any Error).self) { try WindowState(saved: Data("not a window".utf8)) }
    }

    @Test func aWindowOnAnAccountThatIsGoneFallsBackToTheInbox() {
        let label = Mailbox(labelID: "Label_7", accountID: home)
        let thread = ThreadSummary.ID(accountID: home, threadID: "t1")
        let state = WindowState(list: .mailbox(label, title: "Family", thread: nil), category: .promotions)
        #expect(state.keeping([work, home]) == state)
        #expect(state.keeping([work]) == WindowState(category: .promotions))

        let unified = WindowState(list: .mailbox(.inbox, title: nil, thread: thread))
        #expect(
            unified.keeping([work]) == WindowState(list: .mailbox(.inbox, title: nil, thread: nil)),
            "the unified Inbox stays, without the gone account's thread")
        #expect(WindowState(list: .snoozed(thread: thread)).keeping([work]) == WindowState(list: .snoozed(thread: nil)))
        #expect(WindowState(list: .scheduled).keeping([]) == WindowState(list: .scheduled))
    }
}
