public import AppIntents
public import Foundation
import MailCore

/// Snoozes conversations until a date: out of the Inbox until then, back at its top, unread, with an alert.
public struct SnoozeThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Snooze Conversations Until"
    public static let description = IntentDescription(
        "Takes conversations out of the Inbox until a date, then brings them back to its top, unread.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Parameter(title: "Until")
    public var date: Date

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Snooze \(\.$threads) until \(\.$date)")
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).snooze(threads.map(\.id), until: date)
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

/// Snoozes conversations for a while, as "two weeks", from now.
public struct SnoozeThreadsForIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Snooze Conversations For"
    public static let description = IntentDescription(
        "Takes conversations out of the Inbox for a while, then brings them back to its top, unread.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Parameter(title: "For")
    public var duration: Duration

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Snooze \(\.$threads) for \(\.$duration)")
    }

    public func perform() async throws -> some IntentResult {
        let wake = Date.now.addingTimeInterval(duration.seconds)
        let change = try await Catalog(host: host).snooze(threads.map(\.id), until: wake)
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

/// Brings snoozed conversations back to the Inbox now.
public struct UnsnoozeThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Unsnooze Conversations"
    public static let description = IntentDescription("Brings snoozed conversations back to the Inbox now.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Unsnooze \(\.$threads)")
    }

    public func perform() async throws -> some IntentResult {
        let change = try await Catalog(host: host).snooze(threads.map(\.id), until: nil)
        await offerUndo(of: [change], named: Self.title, host: host)
        return .result()
    }
}

extension Catalog {
    /// Snoozes the threads still on the device until `date`, or with `nil` wakes them. Returns what undoes it.
    func snooze(_ identifiers: [String], until date: Date?) async throws -> MailCommands.Undo {
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
