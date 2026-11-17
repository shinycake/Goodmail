public import AppIntents
import MailCore

/// Pins conversations to the top of their lists, or unpins them.
public struct PinThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Pin Conversations", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Keeps conversations at the top of their lists, or lets them go.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("Pinned", table: "ShortcutActions"), default: true)
    public var pinned: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity], pinned: Bool) {
        self.threads = threads
        self.pinned = pinned
    }

    public static var parameterSummary: some ParameterSummary {
        When(\.$pinned, .equalTo, true) {
            Summary("Pin \(\.$threads)", table: "ShortcutFlow") { \.$pinned }
        } otherwise: {
            Summary("Unpin \(\.$threads)", table: "ShortcutFlow") { \.$pinned }
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let change = try await Catalog(host: host).pin(pinned, onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
    }
}

/// Mutes conversations, keeping their replies out of the Inbox, or unmutes them.
public struct MuteThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Mute Conversations", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Keeps replies to conversations out of the Inbox, or lets them in.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("Muted", table: "ShortcutActions"), default: true)
    public var muted: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(threads: [ThreadEntity], muted: Bool) {
        self.threads = threads
        self.muted = muted
    }

    public static var parameterSummary: some ParameterSummary {
        When(\.$muted, .equalTo, true) {
            Summary("Mute \(\.$threads)", table: "ShortcutFlow") { \.$muted }
        } otherwise: {
            Summary("Unmute \(\.$threads)", table: "ShortcutFlow") { \.$muted }
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let change = try await Catalog(host: host).perform(muted ? .mute : .unmute, onThreads: threads.map(\.id))
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
    }
}

extension Catalog {
    /// Pins or unpins the threads still on the device, through the commands (ADR-011). Returns what undoes it.
    @discardableResult
    func pin(_ pinned: Bool, onThreads identifiers: [String]) async throws -> MailCommands.Undo {
        // An automation's Find can come up empty; doing nothing then is a success, so the shortcut runs on.
        guard !identifiers.isEmpty else { return MailCommands.Undo() }
        let ids = identifiers.compactMap(EntityID.thread)
        guard !ids.isEmpty else { throw IntentError.gone }
        return try await host.pin(ids, pinned)
    }
}
