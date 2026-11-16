public import AppIntents
import MailCore

/// Archives conversations: takes them out of the Inbox.
public struct ArchiveThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Archive Conversations", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource("Takes conversations out of the Inbox.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
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
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Delete Conversations", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource("Moves conversations to the Trash.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
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
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Mark Conversations Read", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource("Marks conversations read or unread.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("Read", table: "ShortcutActions"), default: true)
    public var read: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity], read: Bool) {
        self.threads = threads
        self.read = read
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$threads) read: \(\.$read)", table: "ShortcutActions")
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).perform(.markRead(read), onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

/// Stars or unstars conversations.
public struct StarThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Star Conversations", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource("Stars or unstars conversations.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("Starred", table: "ShortcutActions"), default: true)
    public var starred: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity], starred: Bool) {
        self.threads = threads
        self.starred = starred
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Star \(\.$threads): \(\.$starred)", table: "ShortcutActions")
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
