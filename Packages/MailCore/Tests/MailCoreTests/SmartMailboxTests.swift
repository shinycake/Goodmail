import Foundation
import Testing

@testable import MailCore

/// Smart mailboxes: saved searches, each a name, a symbol and what its mail must be.
struct SmartMailboxTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "me@example.com", color: .teal, service: .gmail)

    private func facts(from sender: String, labels: Set<String> = [SystemLabel.inbox]) -> MailFacts {
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t"), subject: "Lunch", snippet: "Tomorrow?",
            sender: Contact(name: "Dana", address: sender), date: .now, isUnread: false, messageCount: 1,
            labelIDs: labels)
        return MailFacts(thread: thread, account: account, labelNames: ["Label_9": "Receipts"])
    }

    @Test func theStartingSetKeepsTheSameIDsOnEveryDevice() {
        #expect(SmartMailbox.startingSet.map(\.id.rawValue) == ["unread", "vips", "attachments"])
        #expect(SmartMailbox.startingSet.map(\.name) == [.unread, .vips, .withAttachments])
    }

    @Test func vipsHoldMailFromTheAddressesChosenNow() {
        let vips = SmartMailbox.startingSet[1]
        let dana = facts(from: "Dana@Example.com")
        #expect(!vips.condition(vips: VIPList()).matches(dana), "empty until VIPs are chosen")
        #expect(vips.condition(vips: VIPList(["dana@example.com"])).matches(dana))
        #expect(!vips.condition(vips: VIPList(["noa@example.com"])).matches(dana))
    }

    @Test func aSavedConditionIsTheBoxsOwn() {
        let box = SmartMailbox(
            name: .custom("Dana"), symbol: "person", filter: .condition(.text(.sender, .contains("dana"))))
        #expect(box.condition(vips: VIPList()) == .text(.sender, .contains("dana")))
    }

    @Test func aBoxRoundTripsThroughItsSharedForm() throws {
        let box = SmartMailbox(
            name: .custom("Receipts"), symbol: "doc.text",
            filter: .condition(.any([.label("Receipts"), .flag(.hasAttachments, true)])))
        let data = try JSONEncoder().encode(box)
        #expect(try JSONDecoder().decode(SmartMailbox.self, from: data) == box)
    }

    @Test func anyTextReadsWhatSearchReadsInAWord() {
        let lunch = facts(from: "dana@example.com")
        #expect(MailCondition.text(.anyText, .contains("tomorrow")).matches(lunch), "the preview")
        #expect(MailCondition.text(.anyText, .contains("lunch")).matches(lunch), "the subject")
        #expect(MailCondition.text(.anyText, .contains("dana")).matches(lunch), "the sender")
        #expect(!MailCondition.text(.anyText, .contains("invoice")).matches(lunch))
    }

    @Test func aLabelConditionMatchesTheLabelByIDOrByName() {
        let receipt = facts(from: "shop@example.com", labels: ["Label_9"])
        #expect(MailCondition.label("Label_9").matches(receipt))
        #expect(MailCondition.label("receipts").matches(receipt), "the editor names labels as the reader sees them")
        #expect(!MailCondition.label("Travel").matches(receipt))
    }
}
