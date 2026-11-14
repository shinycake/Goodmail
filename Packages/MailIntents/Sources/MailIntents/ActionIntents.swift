import AppIntents
import MailCore

/// Archives conversations: takes them out of the Inbox.
public struct ArchiveThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Archive Conversations"
    public static let description = IntentDescription("Takes conversations out of the Inbox.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity]) {
        self.threads = threads
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).perform(.archive, onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

/// Moves conversations to the Trash.
public struct TrashThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Delete Conversations"
    public static let description = IntentDescription("Moves conversations to the Trash.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity]) {
        self.threads = threads
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).perform(.trash, onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

/// Marks conversations read or unread.
public struct MarkThreadsReadIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Mark Conversations Read"
    public static let description = IntentDescription("Marks conversations read or unread.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Parameter(title: "Read", default: true)
    public var read: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity], read: Bool) {
        self.threads = threads
        self.read = read
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$threads) read: \(\.$read)")
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).perform(.markRead(read), onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

/// Stars or unstars conversations.
public struct StarThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Star Conversations"
    public static let description = IntentDescription("Stars or unstars conversations.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Parameter(title: "Starred", default: true)
    public var starred: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity], starred: Bool) {
        self.threads = threads
        self.starred = starred
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Star \(\.$threads): \(\.$starred)")
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).perform(.star(starred), onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

extension Catalog {
    /// Applies `action` to the threads still on the device, through the commands (ADR-011). Returns what undoes it.
    @discardableResult
    func perform(_ action: ThreadAction, onThreads identifiers: [String]) async throws -> MailCommands.Undo {
        let ids = identifiers.compactMap(EntityID.thread)
        guard !ids.isEmpty else { throw IntentError.gone }
        return try await host.perform(action, on: ids)
    }
}
