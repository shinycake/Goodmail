public import Foundation

/// A rule as the Settings editor holds it while it's changed: a name, conditions joined by All or Any, actions, and
/// the values as typed. `rule` is what it saves, once every value reads.
public struct RuleDraft: Identifiable, Equatable, Sendable {
    public enum Joiner: CaseIterable, Sendable {
        case all, any
    }

    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var joiner: Joiner
    public var conditions: [ConditionDraft]
    public var actions: [ActionDraft]
    public var stopsOtherRules: Bool

    /// A new rule: on, matching all of one condition on the sender, doing nothing yet.
    public init() {
        id = UUID()
        name = ""
        isEnabled = true
        joiner = .all
        conditions = [ConditionDraft(.text(.sender, .contains, ""))]
        actions = []
        stopsOtherRules = false
    }

    /// The draft of `rule`, or `nil` for one whose condition is more than the editor shows: nested groups, or a
    /// comparison it has no control for.
    public init?(_ rule: MailRule) {
        let (joiner, parts): (Joiner, [MailCondition]) =
            switch rule.condition {
            case .all(let parts): (.all, parts)
            case .any(let parts): (.any, parts)
            case let single: (.all, [single])
            }
        let conditions = parts.compactMap { ConditionDraft(condition: $0) }
        guard conditions.count == parts.count else { return nil }
        id = rule.id
        name = rule.name
        isEnabled = rule.isEnabled
        self.joiner = joiner
        self.conditions = conditions
        actions = rule.actions.map { ActionDraft(action: $0) }
        stopsOtherRules = rule.stopsOtherRules
    }

    /// The rule the draft makes, or `nil` while a value doesn't read: an empty name, a number that isn't one, a
    /// label or keyword left empty, no condition or no action.
    public var rule: MailRule? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = conditions.compactMap(\.condition)
        let actions = actions.compactMap(\.action)
        guard !name.isEmpty, !parts.isEmpty, parts.count == conditions.count, !actions.isEmpty,
            actions.count == self.actions.count
        else { return nil }
        let condition: MailCondition =
            switch joiner {
            case .all: .all(parts)
            case .any: .any(parts)
            }
        return MailRule(
            id: id, name: name, isEnabled: isEnabled, condition: condition, actions: actions,
            stopsOtherRules: stopsOtherRules)
    }
}

/// A length of time as the editor offers it: a whole number of hours, days or weeks.
public enum TimeUnit: CaseIterable, Sendable {
    case hours, days, weeks

    public var seconds: TimeInterval {
        switch self {
        case .hours: 3600
        case .days: 86_400
        case .weeks: 604_800
        }
    }

    /// `seconds` as the largest unit that divides it, as two weeks for 1 209 600.
    static func amount(of seconds: TimeInterval) -> (Int, TimeUnit) {
        let unit = allCases.reversed().first { seconds.truncatingRemainder(dividingBy: $0.seconds) == 0 } ?? .hours
        return (Int((seconds / unit.seconds).rounded()), unit)
    }
}

/// One condition in the editor, with its value as typed.
public struct ConditionDraft: Identifiable, Equatable, Sendable {
    public enum TextTest: CaseIterable, Sendable {
        case contains, doesNotContain, equals, beginsWith, endsWith, matchesPattern, isEmpty, isNotEmpty

        /// Whether the test compares with a value the reader types.
        public var takesValue: Bool { self != .isEmpty && self != .isNotEmpty }
    }

    public enum NumberTest: CaseIterable, Sendable {
        case equals, lessThan, greaterThan, atMost, atLeast
    }

    public enum Kind: Equatable, Sendable {
        case text(TextField, TextTest, String)
        case number(NumberField, NumberTest, String)
        case flag(MailFlag, Bool)
        case receivedWithin(Int, TimeUnit)
        case weekdays(Set<Weekday>)
        case timeOfDay(from: TimeOfDay, to: TimeOfDay)
        case label(String)
    }

    public let id: UUID
    public var kind: Kind

    public init(_ kind: Kind) {
        id = UUID()
        self.kind = kind
    }

    /// The draft of one part of a rule's condition, or `nil` for a part the editor has no control for.
    public init?(condition: MailCondition) {
        let kind: Kind
        switch condition {
        case .text(let field, let match):
            let (test, value): (TextTest, String) =
                switch match {
                case .contains(let value): (.contains, value)
                case .equals(let value): (.equals, value)
                case .beginsWith(let value): (.beginsWith, value)
                case .endsWith(let value): (.endsWith, value)
                case .matchesPattern(let value): (.matchesPattern, value)
                case .isEmpty: (.isEmpty, "")
                }
            kind = .text(field, test, value)
        case .not(.text(let field, .contains(let value))): kind = .text(field, .doesNotContain, value)
        case .not(.text(let field, .isEmpty)): kind = .text(field, .isNotEmpty, "")
        case .number(let field, let match):
            let test: NumberTest
            let value: Double
            switch match {
            case .equals(let number): (test, value) = (.equals, number)
            case .lessThan(let number): (test, value) = (.lessThan, number)
            case .greaterThan(let number): (test, value) = (.greaterThan, number)
            case .atMost(let number): (test, value) = (.atMost, number)
            case .atLeast(let number): (test, value) = (.atLeast, number)
            case .between: return nil
            }
            kind = .number(field, test, Self.text(of: value / field.draftScale))
        case .flag(let flag, let value): kind = .flag(flag, value)
        case .date(.date, .withinLast(let seconds)):
            let (amount, unit) = TimeUnit.amount(of: seconds)
            kind = .receivedWithin(amount, unit)
        case .weekday(let days): kind = .weekdays(days)
        case .timeOfDay(let from, let to): kind = .timeOfDay(from: from, to: to)
        case .label(let name): kind = .label(name)
        default: return nil
        }
        id = UUID()
        self.kind = kind
    }

    /// The condition, or `nil` while its value doesn't read.
    public var condition: MailCondition? {
        switch kind {
        case .text(let field, let test, let value):
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !test.takesValue || !value.isEmpty else { return nil }
            return switch test {
            case .contains: .text(field, .contains(value))
            case .doesNotContain: .not(.text(field, .contains(value)))
            case .equals: .text(field, .equals(value))
            case .beginsWith: .text(field, .beginsWith(value))
            case .endsWith: .text(field, .endsWith(value))
            case .matchesPattern: (try? Regex(value)) == nil ? nil : .text(field, .matchesPattern(value))
            case .isEmpty: .text(field, .isEmpty)
            case .isNotEmpty: .not(.text(field, .isEmpty))
            }
        case .number(let field, let test, let text):
            guard let typed = Double(text.trimmingCharacters(in: .whitespaces)) else { return nil }
            let value = typed * field.draftScale
            return switch test {
            case .equals: .number(field, .equals(value))
            case .lessThan: .number(field, .lessThan(value))
            case .greaterThan: .number(field, .greaterThan(value))
            case .atMost: .number(field, .atMost(value))
            case .atLeast: .number(field, .atLeast(value))
            }
        case .flag(let flag, let value): return .flag(flag, value)
        case .receivedWithin(let amount, let unit):
            return amount > 0 ? .date(.date, .withinLast(seconds: Double(amount) * unit.seconds)) : nil
        case .weekdays(let days): return days.isEmpty ? nil : .weekday(days)
        case .timeOfDay(let from, let to): return .timeOfDay(from: from, to: to)
        case .label(let name):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .label(name)
        }
    }

    /// A number as the reader would type it: 2, not 2.0.
    private static func text(of value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

/// One action in the editor, with its value as typed.
public struct ActionDraft: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case markRead, star, markImportant, archive, trash, reportSpam, pin, mute
        case move(toLabel: String)
        case addLabel(String)
        case snooze(Int, TimeUnit)
        case notify(keyword: String)
    }

    public let id: UUID
    public var kind: Kind

    public init(_ kind: Kind) {
        id = UUID()
        self.kind = kind
    }

    public init(action: RuleAction) {
        id = UUID()
        switch action {
        case .markRead: kind = .markRead
        case .star: kind = .star
        case .markImportant: kind = .markImportant
        case .archive: kind = .archive
        case .trash: kind = .trash
        case .reportSpam: kind = .reportSpam
        case .pin: kind = .pin
        case .mute: kind = .mute
        case .move(let label): kind = .move(toLabel: label)
        case .addLabel(let label): kind = .addLabel(label)
        case .snooze(let seconds):
            let (amount, unit) = TimeUnit.amount(of: seconds)
            kind = .snooze(amount, unit)
        case .notify(let keyword): kind = .notify(keyword: keyword)
        }
    }

    /// The action, or `nil` while its label or keyword is empty or its length isn't positive.
    public var action: RuleAction? {
        func trimmed(_ text: String) -> String? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return switch kind {
        case .markRead: .markRead
        case .star: .star
        case .markImportant: .markImportant
        case .archive: .archive
        case .trash: .trash
        case .reportSpam: .reportSpam
        case .pin: .pin
        case .mute: .mute
        case .move(let label): trimmed(label).map { .move(toLabel: $0) }
        case .addLabel(let label): trimmed(label).map(RuleAction.addLabel)
        case .snooze(let amount, let unit): amount > 0 ? .snooze(seconds: Double(amount) * unit.seconds) : nil
        case .notify(let keyword): trimmed(keyword).map { .notify(keyword: $0) }
        }
    }
}

extension NumberField {
    /// What a number typed in the editor is multiplied by: attachment sizes are typed in megabytes.
    var draftScale: Double { self == .attachmentSize ? 1_000_000 : 1 }
}
