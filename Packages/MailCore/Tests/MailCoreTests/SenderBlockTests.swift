import Foundation
import Testing

@testable import MailCore

/// Block Sender writes a rule that sends the sender's mail to Trash before any other rule sees it.
struct SenderBlockTests {
    private let dana = SenderAddress("dana@example.com")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func facts(from address: String) -> MailFacts {
        let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t"), subject: "Hi", snippet: "",
            sender: Contact(name: nil, address: address), date: now, isUnread: true, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
        return MailFacts(thread: thread, account: account, labelNames: [:])
    }

    @Test func theRuleTrashesTheSendersMailAndStopsTheOthers() {
        let star = MailRule(name: "Star all", condition: .all([]), actions: [.star, .notify(keyword: "New")])
        let rules = RuleBook.blocking(dana, named: "Block Dana", in: [star])

        #expect(rules.map(\.name) == ["Block Dana", "Star all"])
        let book = RuleBook(rules)
        let context = MailCondition.Context(now: now)
        #expect(book.match(facts(from: "DANA@example.com"), in: context).actions == [.trash])
        #expect(book.match(facts(from: "noa@example.com"), in: context).actions == [.star, .notify(keyword: "New")])
    }

    @Test func blockingTwiceKeepsOneRuleUnderItsFirstID() throws {
        let once = RuleBook.blocking(dana, named: "Block Dana", in: [])
        let twice = RuleBook.blocking(dana, named: "Block Dana", in: once)
        #expect(twice == once)
    }

    @Test func aBlockTurnedOffInSettingsIsTurnedOnAgainAndMovedFirst() throws {
        var blocked = RuleBook.blocking(dana, named: "Block Dana", in: [])
        blocked[0].isEnabled = false
        let other = MailRule(name: "Read", condition: .all([]), actions: [.markRead])

        let again = RuleBook.blocking(dana, named: "Block Dana", in: [other] + blocked)

        #expect(again.map(\.name) == ["Block Dana", "Read"])
        #expect(again[0].isEnabled)
        #expect(again[0].id == blocked[0].id)
    }

    @Test func onlyBlockSendersOwnRuleNamesWhoItBlocks() {
        #expect(MailRule.blocking(dana, named: "Block Dana").blockedSender == dana)
        var edited = MailRule.blocking(dana, named: "Block Dana")
        edited.actions = [.archive]
        #expect(edited.blockedSender == nil, "a rule changed in Settings is the reader's own now")
        let lookalike = MailRule(
            name: "Dana", condition: .text(.senderAddress, .contains("dana@example.com")), actions: [.trash],
            stopsOtherRules: true)
        #expect(lookalike.blockedSender == nil)
    }

    @Test("A Mac catches up on all its mail in a run; an iPhone, which may be stopped, takes one batch")
    func catchUpFollowsPresence() {
        #expect(RuleCatchUp(.keepsRunning) == .everything)
        #expect(RuleCatchUp(.suspends) == .oneBatch)
    }
}
