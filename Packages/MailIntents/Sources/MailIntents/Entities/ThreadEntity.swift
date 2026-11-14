import AppIntents
import CoreSpotlight
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
    /// The latest message's date, which Spotlight sorts by.
    var date: Date

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(sender)")
    }

    init(_ thread: ThreadSummary, messages: [MessageEntity]) {
        id = EntityID.string(thread.id)
        sender = thread.sender.displayName
        date = thread.date
        title = thread.subject
        description = thread.snippet.isEmpty ? nil : thread.snippet
        self.messages = messages
    }

    var threadID: ThreadSummary.ID? { EntityID.thread(id) }
}

extension ThreadEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.contentDescription = description
        attributes.authorNames = [sender]
        attributes.contentCreationDate = date
        return attributes
    }
}

public struct ThreadQuery: EntityStringQuery, IndexedEntityQuery {
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

    /// Spotlight lost its copy: index the newest conversations again.
    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer(host: host).refresh()
    }

    public func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription)
        async throws
    {
        let threads = try Catalog(host: host).threads(identifiers, withMessages: false)
        try await SystemSpotlightIndex().index(threads)
    }
}
