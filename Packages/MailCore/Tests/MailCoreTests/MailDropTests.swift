import Foundation
import MailCore
import Testing

/// What dropping dragged conversations on a mailbox row does, and which drops the row refuses.
struct MailDropTests {
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .blue, service: .gmail)
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "me@icloud.com", color: .green, service: .icloud)
    private func thread(_ id: String, of account: Account) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account.id, threadID: id)
    }
    private func label(_ id: String, in account: Account) -> Mailbox { Mailbox(labelID: id, accountID: account.id) }

    private func drop(
        _ threads: [ThreadSummary.ID], from source: Mailbox = .inbox, onto target: Mailbox, among accounts: [Account],
        adding: Bool = false
    ) -> MailDrop {
        MailDrop(dragging: threads, from: source, onto: target, among: accounts, adding: adding)
    }

    @Test func archiveTrashAndSpamDoWhatTheirCommandsDo() {
        let threads = [thread("1", of: gmail)]
        #expect(drop(threads, onto: .allMail, among: [gmail]) == .perform(.archive))
        #expect(drop(threads, onto: .trash, among: [gmail]) == .perform(.trash))
        #expect(drop(threads, onto: .spam, among: [gmail]) == .perform(.reportSpam))
    }

    @Test func leavingSpamOrTrashMovesInsteadSoTheThreadLeavesThemToo() {
        let threads = [thread("1", of: gmail)]
        #expect(drop(threads, from: .trash, onto: .allMail, among: [gmail]) == .move(.archive))
        #expect(drop(threads, from: .trash, onto: .spam, among: [gmail]) == .move(.spam))
        #expect(drop(threads, from: .spam, onto: .trash, among: [gmail]) == .move(.trash))
        #expect(drop(threads, from: .spam, onto: .inbox, among: [gmail]) == .move(.inbox))
    }

    @Test func aFolderOrLabelMovesThere() {
        let threads = [thread("1", of: gmail)]
        let work = label("Label_work", in: gmail)
        #expect(drop(threads, onto: work, among: [gmail]) == .move(.label("Label_work")))
        #expect(drop(threads, from: work, onto: .inbox, among: [gmail]) == .move(.inbox))
    }

    @Test func holdingOptionAddsTheLabelOnAccountsWithLabels() {
        let work = label("Label_work", in: gmail)
        #expect(drop([thread("1", of: gmail)], onto: work, among: [gmail], adding: true) == .addLabel("Label_work"))
        // A folder service keeps a message in one place, so the option changes nothing there.
        let folder = label("Clients", in: icloud)
        #expect(
            drop([thread("1", of: icloud)], onto: folder, among: [icloud], adding: true) == .move(.label("Clients")))
        // And it means nothing on the standard mailboxes.
        #expect(drop([thread("1", of: gmail)], onto: .trash, among: [gmail], adding: true) == .perform(.trash))
    }

    @Test func aRowThatIsNotAPlaceRefuses() {
        let threads = [thread("1", of: gmail)]
        for target in [Mailbox.starred, .sent, .drafts] {
            #expect(drop(threads, onto: target, among: [gmail]) == .refused)
        }
    }

    @Test func theMailboxTheyAreInRefuses() {
        let threads = [thread("1", of: gmail)]
        let work = label("Label_work", in: gmail)
        #expect(drop(threads, onto: .inbox, among: [gmail]) == .refused)
        #expect(drop(threads, from: work, onto: work, among: [gmail]) == .refused)
        #expect(drop(threads, from: .trash, onto: .trash, among: [gmail]) == .refused)
        // The Inbox that blends the accounts holds the same threads as one account's Inbox.
        #expect(drop(threads, onto: label("INBOX", in: gmail), among: [gmail, icloud]) == .refused)
    }

    @Test func severalAccountsKeepTheirMailApart() {
        let both = [gmail, icloud]
        let mine = thread("1", of: gmail)
        // The rows that blend every account are no place to put mail.
        #expect(drop([mine], onto: .trash, among: both) == .refused)
        #expect(drop([mine], onto: .allMail, among: both) == .refused)
        // Another account's mailbox is refused; the thread's own account's is fine.
        #expect(drop([mine], onto: label("Clients", in: icloud), among: both) == .refused)
        #expect(drop([mine], onto: label("TRASH", in: icloud), among: both) == .refused)
        #expect(drop([mine], onto: label("TRASH", in: gmail), among: both) == .perform(.trash))
        #expect(drop([mine], onto: label("Label_work", in: gmail), among: both) == .move(.label("Label_work")))
    }

    @Test func threadsFromTwoAccountsGoNowhere() {
        let mixed = [thread("1", of: gmail), thread("2", of: icloud)]
        #expect(drop(mixed, onto: label("TRASH", in: gmail), among: [gmail, icloud]) == .refused)
    }

    @Test func nothingDraggedRefuses() {
        #expect(drop([], onto: .trash, among: [gmail]) == .refused)
    }
}
