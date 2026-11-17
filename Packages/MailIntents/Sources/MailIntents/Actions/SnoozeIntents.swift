public import AppIntents
public import Foundation
import MailCore

/// Snoozes conversations until a date: out of the Inbox until then, back at its top, unread, with an alert.
public struct SnoozeThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Snooze Conversations Until", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Takes conversations out of the Inbox until a date, then brings them back to its top, unread.",
            table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("Until", table: "ShortcutActions"))
    public var date: Date

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Snooze \(\.$threads) until \(\.$date)", table: "ShortcutActions")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let change = try await Catalog(host: host).snooze(threads.map(\.id), until: date)
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
    }
}

/// Snoozes conversations for a while, as "two weeks", from now.
public struct SnoozeThreadsForIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Snooze Conversations For", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Takes conversations out of the Inbox for a while, then brings them back to its top, unread.",
            table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("For", table: "ShortcutActions"))
    public var duration: Duration

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Snooze \(\.$threads) for \(\.$duration)", table: "ShortcutActions")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let wake = Date.now.addingTimeInterval(duration.seconds)
        let change = try await Catalog(host: host).snooze(threads.map(\.id), until: wake)
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
    }
}

/// Brings snoozed conversations back to the Inbox now.
public struct UnsnoozeThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Unsnooze Conversations", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource("Brings snoozed conversations back to the Inbox now.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Unsnooze \(\.$threads)", table: "ShortcutActions")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let change = try await Catalog(host: host).snooze(threads.map(\.id), until: nil)
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result(value: threads)
    }
}

extension Catalog {
    /// Snoozes the threads still on the device until `date`, or with `nil` wakes them. Returns what undoes it.
    func snooze(_ identifiers: [String], until date: Date?) async throws -> MailCommands.Undo {
        // An automation's Find can come up empty; doing nothing then is a success, so the shortcut runs on.
        guard !identifiers.isEmpty else { return MailCommands.Undo() }
        let ids = identifiers.compactMap(EntityID.thread)
        guard !ids.isEmpty else { throw IntentError.gone }
        return try await host.snooze(ids, until: date)
    }
}

extension Duration {
    /// The whole length in seconds, attoseconds included.
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
