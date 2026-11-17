import Foundation
import Testing

@testable import MailCore

/// Which rules a message meets, and what they do together.
struct RuleBookTests {
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func facts(from address: String, subject: String = "Hello") -> MailFacts {
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t"), subject: subject, snippet: "",
            sender: Contact(name: nil, address: address), date: now, isUnread: true, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
        return MailFacts(thread: thread, account: account, labelNames: [:])
    }

    private func rule(
        _ name: String, from address: String, _ actions: [RuleAction], stops: Bool = false, enabled: Bool = true
    ) -> MailRule {
        MailRule(
            name: name, isEnabled: enabled, condition: .text(.senderAddress, .equals(address)), actions: actions,
            stopsOtherRules: stops)
    }

    @Test func everyMatchingRuleAddsItsActionsOnceInOrder() {
        let book = RuleBook([
            rule("Read", from: "dana@example.com", [.markRead, .star]),
            rule("Other", from: "noa@example.com", [.trash]),
            rule("Archive", from: "dana@example.com", [.star, .archive]),
        ])
        let match = book.match(facts(from: "dana@example.com"), in: MailCondition.Context(now: now))
        #expect(match.rules.map(\.name) == ["Read", "Archive"])
        #expect(match.actions == [.markRead, .star, .archive])
    }

    @Test func aRuleThatStopsTheOthersEndsTheMatch() {
        let book = RuleBook([
            rule("First", from: "dana@example.com", [.pin], stops: true),
            rule("Second", from: "dana@example.com", [.trash]),
        ])
        #expect(book.match(facts(from: "dana@example.com"), in: MailCondition.Context(now: now)).actions == [.pin])
    }

    @Test func aTurnedOffRuleNeitherActsNorStopsTheOthers() {
        let book = RuleBook([
            rule("Off", from: "dana@example.com", [.trash], stops: true, enabled: false),
            rule("On", from: "dana@example.com", [.archive]),
        ])
        #expect(book.match(facts(from: "dana@example.com"), in: MailCondition.Context(now: now)).actions == [.archive])
    }

    @Test func labelsAreFoundByNameInTheMessagesAccount() {
        let labels = [
            MailLabel(id: "Label_7", name: "Receipts", kind: .user),
            MailLabel(id: "INBOX", name: "INBOX", kind: .system),
        ]
        let inInbox: Set<String> = [SystemLabel.inbox]
        #expect(
            Step(.addLabel("receipts"), labels: labels, in: inInbox, now: now)
                == .perform(.modifyLabels(add: ["Label_7"], remove: [])))
        #expect(
            Step(.move(toLabel: "Receipts"), labels: labels, in: inInbox, now: now)
                == .perform(.move(to: .label("Label_7"), from: Mailbox(labelID: SystemLabel.inbox))))
        #expect(Step(.addLabel("Missing"), labels: labels, in: inInbox, now: now) == .skip)
        #expect(
            Step(.addLabel("INBOX"), labels: labels, in: inInbox, now: now) == .skip, "only the reader's own labels")
        #expect(Step(.snooze(seconds: 60), labels: [], in: inInbox, now: now) == .snooze(until: now + 60))
    }
}
