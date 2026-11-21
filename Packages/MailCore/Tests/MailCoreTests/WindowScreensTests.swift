import MailCore
import Testing

/// What each of a viewer's arrangements shows for a window's state.
struct WindowScreensTests {
    private let label = Mailbox(labelID: "Label_7", accountID: AccountID(rawValue: "work"))
    private var reading: Reading {
        Reading(ThreadSummary.ID(accountID: AccountID(rawValue: "work"), threadID: "t1"), in: .allMail)
    }

    @Test func aNarrowWindowStacksTheMailboxesTheListAndTheConversationReadOverIt() {
        var state = WindowState(list: .mailbox(label))
        #expect(state.stack == [.mailboxes, .list(.mailbox(label))])
        state.read(reading)
        #expect(state.stack == [.mailboxes, .list(.mailbox(label)), .reader(reading)])
    }

    @Test func aNarrowWindowBackAtTheMailboxesShowsThemAloneAndKeepsItsListForAWideOne() {
        var state = WindowState(list: .mailbox(label))
        state.read(reading)
        state.backToMailboxes()
        #expect(state.stack == [.mailboxes])
        #expect(state.columns == WindowState.Columns(list: .mailbox(label), detail: .nothing))
    }

    @Test func aWideWindowShowsTheListAndWhatReadsBesideIt() {
        var state = WindowState(list: .scheduled)
        #expect(state.columns == WindowState.Columns(list: .scheduled, detail: .nothing))
        state.read(reading)
        #expect(state.columns == WindowState.Columns(list: .scheduled, detail: .reader(reading)))
    }
}
