public import Foundation

/// A rule the reader keeps: what it does to mail that arrives and meets its condition, as "snooze for two weeks
/// what arrives on a Thursday night from Dana with three or more people on CC". Rules run on each new message once,
/// whichever process fetched it first (`RuleRunner`).
public struct MailRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var condition: MailCondition
    /// Done in order to each message that meets `condition`.
    public var actions: [RuleAction]
    /// Whether the rules after this one leave alone the mail it acted on.
    public var stopsOtherRules: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        condition: MailCondition,
        actions: [RuleAction],
        stopsOtherRules: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.condition = condition
        self.actions = actions
        self.stopsOtherRules = stopsOtherRules
    }
}

/// What a rule does to a conversation that a matching message arrived in.
public enum RuleAction: Codable, Hashable, Sendable {
    case markRead
    case star
    case markImportant
    case archive
    case trash
    case reportSpam
    /// Out of the Inbox into the label or folder with this name, in the message's account.
    case move(toLabel: String)
    /// The label with this name, in the message's account, leaving the conversation where it is.
    case addLabel(String)
    /// Out of the Inbox for this long, then back at its top, unread.
    case snooze(seconds: TimeInterval)
    case pin
    case mute
    /// A notification of its own whose title is `keyword`, which a Shortcuts automation on notifications from the
    /// app can watch for and run with.
    case notify(keyword: String)
}

/// Rules in the order they run.
public struct RuleBook: Sendable {
    public var rules: [MailRule]

    public init(_ rules: [MailRule]) {
        self.rules = rules
    }

    /// What the enabled rules do to the mail `facts` describes: each matching rule's actions in turn, each action
    /// once, up to the first matching rule that stops the others.
    public func match(_ facts: MailFacts, in context: MailCondition.Context) -> RuleMatch {
        var match = RuleMatch()
        for rule in rules where rule.isEnabled && rule.condition.matches(facts, in: context) {
            match.rules.append(rule)
            for action in rule.actions where !match.actions.contains(action) { match.actions.append(action) }
            if rule.stopsOtherRules { break }
        }
        return match
    }
}

/// The rules one message met, and what they do together.
public struct RuleMatch: Equatable, Sendable {
    public var rules: [MailRule] = []
    public var actions: [RuleAction] = []

    public init() {}
}
