public import Foundation

/// What a mail must be for a filter or a rule to take it: one comparison of a field, or a group of conditions.
/// Shortcuts' Find and Filter actions build these from the entities' properties, and rules keep them saved.
public indirect enum MailCondition: Codable, Hashable, Sendable {
    /// Every condition holds. An empty group always does.
    case all([MailCondition])
    /// At least one condition holds. An empty group never does.
    case any([MailCondition])
    case not(MailCondition)
    case text(TextField, TextMatch)
    case number(NumberField, NumberMatch)
    case date(DateField, DateMatch)
    case flag(MailFlag, Bool)
    /// Sent on one of these days, in the calendar's time zone.
    case weekday(Set<Weekday>)
    /// Sent from `from` up to, not including, `to`. A range that ends before it starts runs past midnight.
    case timeOfDay(from: TimeOfDay, to: TimeOfDay)
    case category(InboxCategory)
    /// In the label or folder with this ID, or the standard mailbox, as `INBOX`, or in one with this name, as the
    /// rules editor names labels.
    case label(String)
    case account(AccountID)

    /// What dates, weekdays and times are read against.
    public struct Context: Sendable {
        public var now: Date
        public var calendar: Calendar

        public init(now: Date = .now, calendar: Calendar = .current) {
            self.now = now
            self.calendar = calendar
        }
    }

    /// Whether `mail` meets the condition. A condition the mail can't answer, as one on the body of a conversation
    /// only listed so far, doesn't hold, and neither does its negation.
    public func matches(_ mail: MailFacts, in context: Context = Context()) -> Bool {
        evaluate(mail, in: context) == true
    }

    /// Three-valued: `nil` when the mail can't know. `all` is false once any part is, `any` true once any part is;
    /// otherwise an unknown part leaves the group unknown.
    public func evaluate(_ mail: MailFacts, in context: Context) -> Bool? {
        switch self {
        case .all(let conditions):
            let results = conditions.map { $0.evaluate(mail, in: context) }
            if results.contains(false) { return false }
            return results.contains(nil) ? nil : true
        case .any(let conditions):
            let results = conditions.map { $0.evaluate(mail, in: context) }
            if results.contains(true) { return true }
            return results.contains(nil) ? nil : false
        case .not(let condition):
            return condition.evaluate(mail, in: context).map(!)
        case .text(let field, let match):
            return mail.texts(field).map(match.matches)
        case .number(let field, let match):
            guard let value = mail.number(field) else {
                // A body that names no amount is known not to name one over 10.
                return mail.content == nil ? nil : false
            }
            return match.matches(value)
        case .date(let field, let match):
            return mail.date(field).map { match.matches($0, now: context.now) } ?? false
        case .flag(let flag, let value):
            return mail.flag(flag).map { $0 == value }
        case .weekday(let days):
            let day = context.calendar.component(.weekday, from: mail.envelope.date)
            return Weekday(rawValue: day).map(days.contains) ?? false
        case .timeOfDay(let from, let to):
            let parts = context.calendar.dateComponents([.hour, .minute], from: mail.envelope.date)
            let time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            return from <= to ? (from <= time && time < to) : (time >= from || time < to)
        case .category(let category):
            return mail.category == category
        case .label(let label):
            let name = TextMatch.fold(label)
            return mail.envelope.labelIDs.contains {
                $0 == label || mail.labelNames[$0].map { TextMatch.fold($0) == name } == true
            }
        case .account(let id):
            return mail.envelope.account.id == id
        }
    }
}

extension MailCondition {
    /// The dates a mail must be sent between to meet the condition, as far as its top-level `all` says, so a store
    /// can read only those. `nil` ends are open.
    public func dateBounds(now: Date) -> (from: Date?, to: Date?) {
        switch self {
        case .date(.date, let match):
            switch match {
            case .before(let date): (nil, date)
            case .after(let date): (date, nil)
            case .between(let start, let end): (start, end)
            case .withinLast(let seconds): (now.addingTimeInterval(-seconds), now)
            }
        case .all(let conditions):
            conditions.map { $0.dateBounds(now: now) }.reduce((nil, nil)) { bounds, next in
                (
                    [bounds.from, next.from].compactMap(\.self).max(),
                    [bounds.to, next.to].compactMap(\.self).min()
                )
            }
        default: (nil, nil)
        }
    }
}

extension TextMatch {
    /// Whether any of `values` matches; `isEmpty` asks whether none has any text.
    func matches(_ values: [String]) -> Bool {
        switch self {
        case .isEmpty: return values.allSatisfy(\.isEmpty)
        case .matchesPattern(let pattern):
            guard let regex = try? Regex(pattern).ignoresCase() else { return false }
            return values.contains { $0.contains(regex) }
        case .contains(let text): return values.contains { Self.fold($0).contains(Self.fold(text)) }
        case .equals(let text): return values.contains { Self.fold($0) == Self.fold(text) }
        case .beginsWith(let text): return values.contains { Self.fold($0).hasPrefix(Self.fold(text)) }
        case .endsWith(let text): return values.contains { Self.fold($0).hasSuffix(Self.fold(text)) }
        }
    }

    /// Without case or diacritics, so "Café" and "cafe" match, as Shortcuts' comparisons do, and Hebrew with vowel
    /// points matches Hebrew without. Drops the combining marks of the canonical decomposition, which works the same
    /// on every platform, where `folding(options:)` ignores diacritics only on Apple's.
    static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(
            contentsOf: text.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
                $0.properties.generalCategory != .nonspacingMark
            })
        return String(scalars).lowercased()
    }
}

extension NumberMatch {
    func matches(_ value: Double) -> Bool {
        switch self {
        case .equals(let other): value == other
        case .lessThan(let other): value < other
        case .greaterThan(let other): value > other
        case .atMost(let other): value <= other
        case .atLeast(let other): value >= other
        case .between(let low, let high): low <= value && value <= high
        }
    }
}

extension DateMatch {
    func matches(_ date: Date, now: Date) -> Bool {
        switch self {
        case .before(let other): date < other
        case .after(let other): date > other
        case .between(let start, let end): start <= date && date <= end
        case .withinLast(let seconds): now.addingTimeInterval(-seconds) <= date && date <= now
        }
    }
}
