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

    public static var parameterSummary: some ParameterSummary {
        Summary("Archive \(\.$threads)", table: "ShortcutFlow")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let change = try await Catalog(host: host).perform(.archive, onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
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

    public static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$threads)", table: "ShortcutFlow")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let change = try await Catalog(host: host).perform(.trash, onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
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
        When(\.$read, .equalTo, true) {
            Summary("Mark \(\.$threads) as read", table: "ShortcutFlow") { \.$read }
        } otherwise: {
            Summary("Mark \(\.$threads) as unread", table: "ShortcutFlow") { \.$read }
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let change = try await Catalog(host: host).perform(.markRead(read), onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
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
        When(\.$starred, .equalTo, true) {
            Summary("Star \(\.$threads)", table: "ShortcutFlow") { \.$starred }
        } otherwise: {
            Summary("Unstar \(\.$threads)", table: "ShortcutFlow") { \.$starred }
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let change = try await Catalog(host: host).perform(.star(starred), onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
    }
}

extension Catalog {
    /// Applies `action` to the threads still on the device, through the commands (ADR-011). Returns what undoes it.
    @discardableResult
    func perform(_ action: ThreadAction, onThreads identifiers: [String]) async throws -> MailCommands.Undo {
        // An automation's Find can come up empty; doing nothing then is a success, so the shortcut runs on.
        guard !identifiers.isEmpty else { return MailCommands.Undo() }
        let ids = identifiers.compactMap(EntityID.thread)
        guard !ids.isEmpty else { throw IntentError.gone }
        return try await host.perform(action, on: ids)
    }
}
