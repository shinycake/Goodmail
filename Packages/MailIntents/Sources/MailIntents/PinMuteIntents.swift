import AppIntents
import MailCore

/// Pins conversations to the top of their lists, or unpins them.
public struct PinThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Pin Conversations"
    public static let description = IntentDescription("Keeps conversations at the top of their lists, or lets them go.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Parameter(title: "Pinned", default: true)
    public var pinned: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity], pinned: Bool) {
        self.threads = threads
        self.pinned = pinned
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Pin \(\.$threads): \(\.$pinned)")
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).pin(pinned, onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

/// Mutes conversations, keeping their replies out of the Inbox, or unmutes them.
public struct MuteThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Mute Conversations"
    public static let description = IntentDescription(
        "Keeps replies to conversations out of the Inbox, or lets them in.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Parameter(title: "Muted", default: true)
    public var muted: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity], muted: Bool) {
        self.threads = threads
        self.muted = muted
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Mute \(\.$threads): \(\.$muted)")
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).perform(muted ? .mute : .unmute, onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

extension Catalog {
    /// Pins or unpins the threads still on the device, through the commands (ADR-011). Returns what undoes it.
    @discardableResult
    func pin(_ pinned: Bool, onThreads identifiers: [String]) async throws -> MailCommands.Undo {
        let ids = identifiers.compactMap(EntityID.thread)
        guard !ids.isEmpty else { throw IntentError.gone }
        return try await host.pin(ids, pinned)
    }
}
