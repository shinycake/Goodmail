import AppIntents
import MailCore

// The mail domain's own intents, which Siri and Apple Intelligence call with message entities. Goodmail changes
// whole conversations, as Gmail's threads do, so each acts on the messages' threads.

@AppIntent(schema: .mail.archiveMail)
public struct ArchiveMailIntent {
    public var entities: [MessageEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await Catalog(host: host).perform(.archive, onMessages: entities.map(\.id))
        return .result()
    }
}

@AppIntent(schema: .mail.deleteMail)
public struct DeleteMailIntent: DeleteIntent {
    public var entities: [MessageEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await Catalog(host: host).perform(.trash, onMessages: entities.map(\.id))
        return .result()
    }
}

/// Marks messages read, flagged, junk or not junk, or moves them to a mailbox; each change it's given, in that order.
@AppIntent(schema: .mail.updateMail)
public struct UpdateMailIntent {
    public var target: [MessageEntity]
    public var isRead: Bool?
    public var isFlagged: Bool?
    public var isJunk: Bool?
    public var mailbox: MailboxEntity?

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult {
        let catalog = Catalog(host: host)
        let ids = target.map(\.id)
        for action in Self.actions(isRead: isRead, isFlagged: isFlagged, isJunk: isJunk) {
            try await catalog.perform(action, onMessages: ids)
        }
        if isJunk == false { try await catalog.markNotJunk(target) }
        if let destination = mailbox?.mailbox.flatMap(MoveDestination.init) {
            try await catalog.move(messages: target, to: destination)
        }
        return .result()
    }

    /// The thread actions for the flags it's given. Not junk isn't one: it applies only to the messages in Junk.
    static func actions(isRead: Bool?, isFlagged: Bool?, isJunk: Bool?) -> [ThreadAction] {
        [
            isRead.map(ThreadAction.markRead),
            isFlagged.map(ThreadAction.star),
            isJunk == true ? .reportSpam : nil,
        ].compactMap(\.self)
    }
}

extension Catalog {
    /// Applies `action` to the threads of the messages.
    func perform(_ action: ThreadAction, onMessages identifiers: [String]) async throws {
        let threads = Set(identifiers.compactMap { EntityID.message($0)?.thread })
        try await perform(action, onThreads: threads.map(EntityID.string))
    }

    /// Takes the messages in Junk back to the Inbox. Messages anywhere else are already not junk, and stay put.
    func markNotJunk(_ messages: [MessageEntity]) async throws {
        let junk = messages.filter { $0.mailbox.mailbox?.labelID == SystemLabel.spam }
        guard !junk.isEmpty else { return }
        try await perform(.moveToInbox, onMessages: junk.map(\.id))
    }

    /// Moves the messages' threads from the mailbox each is in to `destination`.
    func move(messages: [MessageEntity], to destination: MoveDestination) async throws {
        for message in messages {
            guard let source = message.mailbox.mailbox, let thread = message.threadID else { continue }
            try await host.perform(.move(to: destination, from: Mailbox(labelID: source.labelID)), on: [thread])
        }
    }
}
