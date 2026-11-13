import AppIntents
import MailCore

/// A conversation, as Siri, Shortcuts and Spotlight see it.
@AppEntity(schema: .mail.thread)
public struct ThreadEntity {
    public static let defaultQuery = ThreadQuery()

    public let id: String
    public var title: String
    public var description: String?
    /// The messages cached on the device, oldest first. A thread only listed so far has none yet.
    public var messages: [MessageEntity]
    /// The latest message's sender, for the subtitle.
    var sender: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(sender)")
    }

    init(_ thread: ThreadSummary, messages: [MessageEntity]) {
        id = EntityID.string(thread.id)
        sender = thread.sender.displayName
        title = thread.subject
        description = thread.snippet.isEmpty ? nil : thread.snippet
        self.messages = messages
    }

    var threadID: ThreadSummary.ID? { EntityID.thread(id) }
}

public struct ThreadQuery: EntityStringQuery {
    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func entities(for identifiers: [String]) async throws -> [ThreadEntity] {
        try Catalog(host: host).threads(identifiers)
    }

    public func entities(matching string: String) async throws -> [ThreadEntity] {
        try Catalog(host: host).threads(matching: string)
    }

    public func suggestedEntities() async throws -> [ThreadEntity] {
        try Catalog(host: host).recentThreads()
    }
}
