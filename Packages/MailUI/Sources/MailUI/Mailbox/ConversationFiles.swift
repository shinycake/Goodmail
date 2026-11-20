public import MailCore
public import UIKit
import UniformTypeIdentifiers

/// Where a dragged conversation's messages come from: which they are, and the RFC 5322 bytes of each. Both go to the
/// provider or the store, never on the main actor.
public struct ConversationSources: Sendable {
    /// A conversation's messages, oldest first.
    public var messages: @Sendable (ThreadSummary.ID) async throws -> [Message.ID]
    /// A message as the service keeps it, to write as an `.eml` file.
    public var source: @Sendable (Message.ID) async throws -> Data

    public init(
        messages: @escaping @Sendable (ThreadSummary.ID) async throws -> [Message.ID],
        source: @escaping @Sendable (Message.ID) async throws -> Data
    ) {
        self.messages = messages
        self.source = source
    }
}

/// The messages of the conversations one drag carries, looked up once for each conversation however many of its files
/// the drop asks for.
private actor MessageLists {
    private let lookup: @Sendable (ThreadSummary.ID) async throws -> [Message.ID]
    private var lists: [ThreadSummary.ID: Task<[Message.ID], any Error>] = [:]

    init(_ lookup: @escaping @Sendable (ThreadSummary.ID) async throws -> [Message.ID]) {
        self.lookup = lookup
    }

    func messages(of thread: ThreadSummary.ID) async throws -> [Message.ID] {
        if let list = lists[thread] { return try await list.value }
        let list = Task { [lookup] in try await lookup(thread) }
        lists[thread] = list
        return try await list.value
    }
}

/// One drag's `.eml` files. A conversation gives one file for each of its messages, named by its subject as the Share
/// menu names them, and each is made only when the drop asks for it.
struct ConversationFiles: Sendable {
    private let sources: ConversationSources
    private let lists: MessageLists

    init(_ sources: ConversationSources) {
        self.sources = sources
        lists = MessageLists(sources.messages)
    }

    /// The drag items for `thread`'s messages, each carrying `payload` for a drop inside the app.
    func items(for thread: ThreadSummary, carrying payload: DraggedThread) -> [UIDragItem] {
        // The count the list shows. The files come from the conversation's own list when they are asked for.
        let fallback = String(
            localized: "Message", table: "Mailbox", bundle: .module,
            comment: "File name of a dragged email that has no subject")
        let names = ExportFilename.names(
            for: thread.subject, count: max(thread.messageCount, 1), fallback: fallback, extension: "eml")
        return names.enumerated().map { position, name in
            let provider = NSItemProvider()
            provider.suggestedName = name
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.emailMessage.identifier, visibility: .all
            ) { deliver in
                let work = Task {
                    do {
                        deliver(try await source(ofMessageAt: position, in: thread.id), nil)
                    } catch {
                        deliver(nil, error)
                    }
                }
                let progress = Progress(totalUnitCount: 1)
                progress.cancellationHandler = { work.cancel() }
                return progress
            }
            let item = UIDragItem(itemProvider: provider)
            item.localObject = payload
            return item
        }
    }

    /// The source of the conversation's `position`th message, oldest first. Past the end, when the conversation lost
    /// messages since the list showed it, there is no file.
    private func source(ofMessageAt position: Int, in thread: ThreadSummary.ID) async throws -> Data {
        let messages = try await lists.messages(of: thread)
        guard messages.indices.contains(position) else { throw ProviderError.notFound }
        return try await sources.source(messages[position])
    }
}
