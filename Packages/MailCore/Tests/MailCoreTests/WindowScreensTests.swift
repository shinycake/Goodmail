import MailCore
import Testing

/// What a narrow window's stack shows for a window's state.
struct WindowScreensTests {
    private let label = Mailbox(labelID: "Label_7", accountID: AccountID(rawValue: "work"))
    private var reading: Reading {
        Reading(ThreadSummary.ID(accountID: AccountID(rawValue: "work"), threadID: "t1"), in: .allMail)
    }

    @Test func aNarrowWindowStacksTheMailboxesTheListAndTheConversationReadOverIt() {
        var state = WindowState(list: .mailbox(label))
        #expect(state.stack == [.mailboxes, .list])
        state.read(reading)
        #expect(state.stack == [.mailboxes, .list, .reader(reading)])
    }

    @Test func aNarrowWindowBackAtTheMailboxesShowsThemAloneAndKeepsItsListForAWideOne() {
        var state = WindowState(list: .mailbox(label))
        state.read(reading)
        state.backToMailboxes()
        #expect(state.stack == [.mailboxes])
        #expect(state.list == .mailbox(label) && state.reading == nil, "what a wide window shows beside them")
    }

    @Test func aMessageWindowShowsItsConversationAlone() {
        let message = WindowState(list: .mailbox(label)).opening(reading, as: .message)
        #expect(message.stack == [.reader(reading)])
    }
}
