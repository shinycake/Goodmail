import MailCore
import Testing

@testable import MailIntents

struct EntityIDTests {
    private let account = AccountID(rawValue: "A1")

    /// Gmail's hex IDs, an iCloud Message-ID and folder-named message key, and Outlook's base64 IDs.
    static let providerIDs = [
        ("18c2f0a9b", "18c2f0a9b1"),
        ("<CAF+x/abc%20@mail.gmail.com>", "INBOX/Sub\n123\n45"),
        ("AAQkADAwATM3ZmYAZS1kYjAwLTg/xyz=", "AAMkAGI2T/G+0vAAA="),
    ]

    @Test(arguments: providerIDs)
    func threadAndMessageIdentifiersRoundTrip(thread: String, message: String) {
        let threadID = ThreadSummary.ID(accountID: account, threadID: thread)
        #expect(EntityID.thread(EntityID.string(threadID)) == threadID)

        let messageID = Message.ID(accountID: account, messageID: message)
        let decoded = EntityID.message(EntityID.string(messageID, inThread: thread))
        #expect(decoded?.thread == threadID)
        #expect(decoded?.message == messageID)
    }

    @Test func mailboxIdentifiersRoundTripIncludingAllMail() {
        for label in ["INBOX", "Label_7", "Work/Clients", nil] {
            let mailbox = Mailbox(labelID: label, accountID: account)
            #expect(EntityID.mailbox(EntityID.string(mailbox, account: account)) == mailbox)
        }
    }

    @Test func malformedIdentifiersAreRejected() {
        #expect(EntityID.thread("A1") == nil)
        #expect(EntityID.thread("A1/") == nil)
        #expect(EntityID.thread("A1/t/extra") == nil)
        #expect(EntityID.message("A1/t") == nil)
        #expect(EntityID.mailbox("/INBOX") == nil)
    }
}
