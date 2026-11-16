import Foundation
import Testing

@testable import MailCore

/// The Settings editor's rule, as typed, and the rule it saves.
struct RuleDraftTests {
    /// Idan's rule, as the editor builds it.
    private var thursdayNight: RuleDraft {
        var draft = RuleDraft()
        draft.name = "  Thursday night "
        draft.conditions = [
            ConditionDraft(.weekdays([.thursday])),
            ConditionDraft(.timeOfDay(from: TimeOfDay(hour: 3, minute: 30), to: TimeOfDay(hour: 4, minute: 0))),
            ConditionDraft(.text(.senderAddress, .equals, "dana@example.com")),
            ConditionDraft(.text(.subject, .contains, "Y")),
            ConditionDraft(.number(.ccCount, .atLeast, "2")),
        ]
        draft.actions = [ActionDraft(.snooze(2, .weeks)), ActionDraft(.notify(keyword: "Snoozed"))]
        return draft
    }

    @Test func aCompleteDraftMakesItsRule() throws {
        let rule = try #require(thursdayNight.rule)
        #expect(rule.name == "Thursday night")
        #expect(
            rule.condition
                == .all([
                    .weekday([.thursday]),
                    .timeOfDay(from: TimeOfDay(hour: 3, minute: 30), to: TimeOfDay(hour: 4, minute: 0)),
                    .text(.senderAddress, .equals("dana@example.com")), .text(.subject, .contains("Y")),
                    .number(.ccCount, .atLeast(2)),
                ]))
        #expect(rule.actions == [.snooze(seconds: 1_209_600), .notify(keyword: "Snoozed")])
    }

    @Test func aRuleOpensAsTheDraftThatMadeIt() throws {
        let rule = try #require(thursdayNight.rule)
        let reopened = try #require(RuleDraft(rule))
        #expect(reopened.rule == rule)
        #expect(reopened.actions.map(\.kind) == [.snooze(2, .weeks), .notify(keyword: "Snoozed")])
        #expect(reopened.conditions.last?.kind == .number(.ccCount, .atLeast, "2"))
    }

    @Test(arguments: [
        ConditionDraft.Kind.text(.subject, .contains, " "), .text(.body, .matchesPattern, "("),
        .number(.ccCount, .atLeast, "two"), .weekdays([]), .label(""), .receivedWithin(0, .days),
    ])
    func aValueThatDoesntReadKeepsTheRuleFromSaving(kind: ConditionDraft.Kind) {
        var draft = thursdayNight
        draft.conditions.append(ConditionDraft(kind))
        #expect(draft.rule == nil)
    }

    @Test func aRuleNeedsANameAConditionAndAnAction() {
        var unnamed = thursdayNight
        unnamed.name = " "
        var idle = thursdayNight
        idle.actions = []
        var blankLabel = thursdayNight
        blankLabel.actions.append(ActionDraft(.move(toLabel: "")))
        var open = thursdayNight
        open.conditions = []
        #expect([unnamed, idle, blankLabel, open].allSatisfy { $0.rule == nil })
    }

    @Test func negativeTestsAreNotsOfTheirPositive() throws {
        var draft = thursdayNight
        draft.joiner = .any
        draft.conditions = [
            ConditionDraft(.text(.body, .doesNotContain, "unsubscribe")),
            ConditionDraft(.text(.cc, .isNotEmpty, "")),
            ConditionDraft(.receivedWithin(3, .days)),
        ]
        let rule = try #require(draft.rule)
        #expect(
            rule.condition
                == .any([
                    .not(.text(.body, .contains("unsubscribe"))), .not(.text(.cc, .isEmpty)),
                    .date(.date, .withinLast(seconds: 3 * 86_400)),
                ]))
        #expect(RuleDraft(rule)?.conditions.map(\.kind) == draft.conditions.map(\.kind))
    }

    @Test func attachmentSizesAreTypedInMegabytes() throws {
        var draft = thursdayNight
        draft.conditions = [ConditionDraft(.number(.attachmentSize, .greaterThan, "2.5"))]
        let rule = try #require(draft.rule)
        #expect(rule.condition == .all([.number(.attachmentSize, .greaterThan(2_500_000))]))
        #expect(RuleDraft(rule)?.conditions.first?.kind == .number(.attachmentSize, .greaterThan, "2.5"))
    }

    @Test func aConditionTheEditorCantShowLeavesTheRuleToShortcuts() {
        let nested = MailRule(name: "Nested", condition: .all([.any([.flag(.unread, true)])]), actions: [.archive])
        let between = MailRule(name: "Range", condition: .number(.ccCount, .between(1, 3)), actions: [.archive])
        #expect(RuleDraft(nested) == nil)
        #expect(RuleDraft(between) == nil)
    }

    @Test(arguments: [(3600.0, 1, TimeUnit.hours), (172_800, 2, .days), (1_209_600, 2, .weeks), (5400, 2, .hours)])
    func lengthsReadInTheLargestWholeUnit(seconds: TimeInterval, amount: Int, unit: TimeUnit) {
        let (found, foundUnit) = TimeUnit.amount(of: seconds)
        #expect(found == amount)
        #expect(foundUnit == unit)
    }
}
