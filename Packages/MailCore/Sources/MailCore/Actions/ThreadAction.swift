import Foundation

/// A change the user makes to a thread. Each applies to the local store at once and replays to the provider from the
/// outbox (ADR-008); replaying one twice leaves the thread the same.
public enum ThreadAction: Codable, Equatable, Sendable {
    case modifyLabels(add: Set<String>, remove: Set<String>)
    case trash
    case untrash

    public static let archive = modifyLabels(add: [], remove: [SystemLabel.inbox])
    public static let moveToInbox = modifyLabels(add: [SystemLabel.inbox], remove: [SystemLabel.spam])
    public static let reportSpam = modifyLabels(add: [SystemLabel.spam], remove: [SystemLabel.inbox])
    /// Gmail's Mute: the thread leaves the Inbox, and replies skip it while `MUTED` stays on.
    public static let mute = modifyLabels(add: [SystemLabel.muted], remove: [SystemLabel.inbox])
    public static let unmute = modifyLabels(add: [SystemLabel.inbox], remove: [SystemLabel.muted])

    public static func markRead(_ read: Bool) -> ThreadAction {
        read
            ? .modifyLabels(add: [], remove: [SystemLabel.unread])
            : .modifyLabels(add: [SystemLabel.unread], remove: [])
    }

    public static func star(_ starred: Bool) -> ThreadAction {
        starred
            ? .modifyLabels(add: [SystemLabel.starred], remove: [])
            : .modifyLabels(add: [], remove: [SystemLabel.starred])
    }

    /// The labels a thread (or message) carries after this action.
    public func applied(to labels: Set<String>) -> Set<String> {
        switch self {
        case .modifyLabels(let add, let remove): labels.subtracting(remove).union(add)
        case .trash: labels.subtracting([SystemLabel.inbox]).union([SystemLabel.trash])
        case .untrash: labels.subtracting([SystemLabel.trash])
        }
    }

    /// The mute action all of these threads, given by their labels and their account's service, allow: Mute when
    /// none is muted, Unmute when all are. `nil` for a mix, for none, for anything in Spam or Trash, where muting
    /// means nothing, and for a service without Mute.
    public static func muting(_ threads: [(labels: Set<String>, service: MailService)]) -> ThreadAction? {
        guard !threads.isEmpty,
            threads.allSatisfy({
                $0.service.hasMute && $0.labels.isDisjoint(with: [SystemLabel.spam, SystemLabel.trash])
            })
        else { return nil }
        if threads.allSatisfy({ !$0.labels.contains(SystemLabel.muted) }) { return .mute }
        return threads.allSatisfy { $0.labels.contains(SystemLabel.muted) } ? .unmute : nil
    }

    /// The actions that put back a thread that carried `labels` before this one. Empty when this one changed nothing.
    public func inverse(given labels: Set<String>) -> [ThreadAction] {
        let after = applied(to: labels)
        let added = after.subtracting(labels)
        let removed = labels.subtracting(after)
        var actions: [ThreadAction] = []
        if added.contains(SystemLabel.trash) { actions.append(.untrash) }
        if removed.contains(SystemLabel.trash) { actions.append(.trash) }
        let addBack = removed.subtracting([SystemLabel.trash])
        let takeOff = added.subtracting([SystemLabel.trash])
        if !addBack.isEmpty || !takeOff.isEmpty { actions.append(.modifyLabels(add: addBack, remove: takeOff)) }
        return actions
    }
}

/// Gmail's system label IDs, which the domain model uses for every provider.
public enum SystemLabel {
    public static let inbox = "INBOX"
    public static let unread = "UNREAD"
    public static let starred = "STARRED"
    public static let trash = "TRASH"
    public static let spam = "SPAM"
    public static let sent = "SENT"
    public static let draft = "DRAFT"
    /// Set by Gmail's Mute. Unlike the others it is not in `labels.list`, but `threads.modify` and fetched threads
    /// carry it.
    public static let muted = "MUTED"
}

/// One queued action: replayed to the provider in the order it was made, then removed.
public struct OutboxIntent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var threadID: String
    public var action: ThreadAction
    public var createdAt: Date

    public init(id: UUID = UUID(), threadID: String, action: ThreadAction, createdAt: Date) {
        self.id = id
        self.threadID = threadID
        self.action = action
        self.createdAt = createdAt
    }
}

/// The persistence the outbox needs. `MailStore` implements it.
public protocol OutboxStore: Sendable {
    /// Applies the intents to the account's local threads and queues them, in one transaction. Returns each thread's
    /// labels from before, for undo; threads that aren't stored are left out and not queued.
    func enqueue(_ intents: [OutboxIntent], account: AccountID) throws -> [String: Set<String>]
    /// Intents not yet sent, oldest first.
    func pendingIntents(for account: AccountID) throws -> [OutboxIntent]
    /// Keeps a sent intent applied over fetches that began before `date`, which may not show it yet; the first
    /// fetch to begin after it clears it.
    func markSent(_ id: OutboxIntent.ID, at date: Date) throws
    /// Forgets an intent that won't be sent, such as one whose thread is gone.
    func removeIntent(_ id: OutboxIntent.ID) throws
}
