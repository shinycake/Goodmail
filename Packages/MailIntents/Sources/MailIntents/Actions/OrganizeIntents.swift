public import AppIntents
import MailCore

/// Moves conversations to a mailbox: the Inbox, Spam, Trash or a label or folder. Gmail's labels act as folders
/// here, as its Move does: the conversation leaves the mailbox it was in.
public struct MoveThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Move Conversations"
    public static let description = IntentDescription(
        "Moves conversations to a mailbox, label or folder, out of the one they're in.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Parameter(title: "Mailbox")
    public var mailbox: MailboxEntity

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Move \(\.$threads) to \(\.$mailbox)")
    }

    public func perform() async throws -> some IntentResult {
        guard let destination = mailbox.mailbox.flatMap(MoveDestination.init) else { throw IntentError.notAPlace }
        let changes = try await Catalog(host: host).move(threads.map(\.id), to: destination)
        await offerUndo(of: changes, named: Self.title, host: host)
        return .result()
    }
}

/// What Label Conversations does with the label.
public enum LabelChange: String, AppEnum {
    case add, remove

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Label Change"
    public static let caseDisplayRepresentations: [LabelChange: DisplayRepresentation] = [
        .add: "Add", .remove: "Remove",
    ]
}

/// Adds a label to conversations, or takes it off, leaving them in every other mailbox they're in.
public struct LabelThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Label Conversations"
    public static let description = IntentDescription(
        "Adds a label to conversations or removes it, without moving them out of anywhere else.")

    @Parameter(title: "Change", default: .add)
    public var change: LabelChange

    @Parameter(title: "Label")
    public var label: MailboxEntity

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("\(\.$change) \(\.$label) on \(\.$threads)")
    }

    public func perform() async throws -> some IntentResult {
        guard let labelID = label.mailbox?.labelID else { throw IntentError.notAPlace }
        let action: ThreadAction =
            switch change {
            case .add: .modifyLabels(add: [labelID], remove: [])
            case .remove: .modifyLabels(add: [], remove: [labelID])
            }
        let undo = try await Catalog(host: host).perform(action, onThreads: threads.map(\.id))
        await offerUndo(of: [undo], named: Self.title, host: host)
        return .result()
    }
}

/// Reports conversations as spam, or takes them out of Spam back to the Inbox.
public struct ReportSpamIntent: UndoableIntent {
    public static let title: LocalizedStringResource = "Report Spam"
    public static let description = IntentDescription(
        "Moves conversations to Spam, or with Spam off takes them back to the Inbox.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Parameter(title: "Spam", default: true)
    public var spam: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Report \(\.$threads) as spam: \(\.$spam)")
    }

    public func perform() async throws -> some IntentResult {
        let undo = try await Catalog(host: host).perform(
            spam ? .reportSpam : .moveToInbox, onThreads: threads.map(\.id))
        await offerUndo(of: [undo], named: Self.title, host: host)
        return .result()
    }
}

/// Deletes the conversations' messages in Trash for good, after asking. Nothing undoes it.
public struct DeleteForeverIntent: AppIntent {
    public static let title: LocalizedStringResource = "Delete Conversations Forever"
    public static let description = IntentDescription(
        "Deletes the messages of conversations that are in Trash for good. Messages anywhere else stay.")

    @Parameter(title: "Conversations")
    public var threads: [ThreadEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$threads) forever")
    }

    public func perform() async throws -> some IntentResult {
        try await requestConfirmation(
            actionName: .custom(
                acceptLabel: "Delete Forever", acceptAlternatives: [], denyLabel: "Cancel", denyAlternatives: [],
                destructive: true),
            dialog: "Delete these conversations' messages in Trash forever? This can't be undone.")
        try await Catalog(host: host).perform(.deleteForever, onThreads: threads.map(\.id))
        return .result()
    }
}

extension Catalog {
    /// Moves each thread from the mailbox it's in to `destination`. Returns what undoes each move.
    func move(_ identifiers: [String], to destination: MoveDestination) async throws -> [MailCommands.Undo] {
        let threads = try host.threads(identifiers.compactMap(EntityID.thread))
        guard !threads.isEmpty else { throw IntentError.gone }
        // Threads in the same mailbox move in one change.
        let bySource = Dictionary(grouping: threads) { Mailbox.holding($0.labelIDs) }
        var changes: [MailCommands.Undo] = []
        for (source, threads) in bySource {
            try await changes.append(host.perform(.move(to: destination, from: source), on: threads.map(\.id)))
        }
        return changes
    }
}
