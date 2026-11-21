import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor @Suite("Window titles and activities")
struct WindowStateTitleTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)
    private var thread: ThreadSummary.ID { ThreadSummary.ID(accountID: account.id, threadID: "t") }

    /// `list` reading the thread, in `mailbox`.
    private func reading(_ list: WindowState.List, in mailbox: Mailbox, category: InboxCategory = .primary)
        -> WindowState
    {
        var state = WindowState(list: list, category: category)
        state.read(Reading(thread, in: mailbox))
        return state
    }

    @Test func aWindowReadingAThreadIsNamedAfterItsSubject() {
        let state = reading(.mailbox(.inbox), in: .inbox)
        #expect(state.windowTitle(subject: "Lunch?", labels: [], accounts: [account]) == "Lunch?")
        #expect(state.windowTitle(subject: "", labels: [], accounts: [account]) == ThreadRowMetrics.noSubject)
    }

    @Test func aThreadGoneFromTheDeviceLeavesTheListsName() {
        let state = reading(.mailbox(.inbox), in: .allMail)
        #expect(state.windowTitle(subject: nil, labels: [], accounts: [account]) == Mailbox.inbox.title(labels: []))
    }

    @Test func aWindowShowingAListIsNamedAfterIt() {
        let label = Mailbox(labelID: "Label_1", accountID: account.id)
        let labels = [MailboxDirectory.Label(mailbox: label, name: "Receipts", color: nil)]
        let state = WindowState(list: .mailbox(label))
        #expect(state.windowTitle(subject: nil, labels: labels, accounts: [account]) == "Receipts")
        let accountInbox = WindowState(
            list: .mailbox(Mailbox(labelID: SystemLabel.inbox, accountID: account.id)))
        #expect(accountInbox.windowTitle(subject: nil, labels: [], accounts: [account]) == account.title)
    }

    @Test func aNarrowWindowBackAtTheMailboxesIsNamedMailboxes() {
        let state = WindowState(place: .mailboxes)
        #expect(state.windowTitle(subject: nil, labels: [], accounts: [account]) == MailboxesViewController.title)
    }

    @Test func aWindowsActivityRestoresItsState() throws {
        let state = reading(.mailbox(.inbox), in: .allMail, category: .updates)
        let activity = try #require(state.activity)
        #expect(WindowState(activity) == state)
        #expect(WindowState(NSUserActivity(activityType: "com.example.other")) == nil)
    }

    @Test func aDraggedRowOpensItsThreadOverItsListOnTheShownCategory() {
        let label = Mailbox(labelID: "Label_1", accountID: account.id)
        let list = MailboxViewModel(
            mailbox: label, accounts: [account], source: .flat { AsyncThrowingStream { $0.finish() } }, refresh: {})
        #expect(list.newWindow(for: thread) == reading(.mailbox(label), in: label))
    }
}
