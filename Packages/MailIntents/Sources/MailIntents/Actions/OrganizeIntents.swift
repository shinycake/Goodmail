public import AppIntents
import MailCore

/// Moves conversations to a mailbox: the Inbox, Spam, Trash or a label or folder. Gmail's labels act as folders
/// here, as its Move does: the conversation leaves the mailbox it was in.
public struct MoveThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Move Conversations", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Moves conversations to a mailbox, label or folder, out of the one they're in.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("Mailbox", table: "ShortcutActions"))
    public var mailbox: MailboxEntity

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Move \(\.$threads) to \(\.$mailbox)", table: "ShortcutActions")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        guard let destination = mailbox.mailbox.flatMap(MoveDestination.init) else { throw IntentError.notAPlace }
        let changes = try await Catalog(host: host).move(threads.map(\.id), to: destination)
        await offerUndo(of: changes, named: Self.title, host: host)
        return .result(value: threads)
    }
}

/// What Label Conversations does with the label.
public enum LabelChange: String, AppEnum {
    case add, remove

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Label Change", table: "ShortcutActions"))
    public static let caseDisplayRepresentations: [LabelChange: DisplayRepresentation] = [
        .add: DisplayRepresentation(title: LocalizedStringResource("Add", table: "ShortcutActions")),
        .remove: DisplayRepresentation(title: LocalizedStringResource("Remove", table: "ShortcutActions")),
    ]
}

/// Adds a label to conversations, or takes it off, leaving them in every other mailbox they're in.
public struct LabelThreadsIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Label Conversations", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Adds a label to conversations or removes it, without moving them out of anywhere else.",
            table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Change", table: "ShortcutActions"), default: .add)
    public var change: LabelChange

    @Parameter(title: LocalizedStringResource("Label", table: "ShortcutActions"))
    public var label: MailboxEntity

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("\(\.$change) \(\.$label) on \(\.$threads)", table: "ShortcutActions")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        guard let labelID = label.mailbox?.labelID else { throw IntentError.notAPlace }
        let action: ThreadAction =
            switch change {
            case .add: .modifyLabels(add: [labelID], remove: [])
            case .remove: .modifyLabels(add: [], remove: [labelID])
            }
        let undo = try await Catalog(host: host).perform(action, onThreads: threads.map(\.id))
        await offerUndo(of: [undo], named: Self.title, host: host)
        return .result(value: threads)
    }
}

/// Reports conversations as spam, or takes them out of Spam back to the Inbox.
public struct ReportSpamIntent: UndoableIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("Report Spam", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Moves conversations to Spam, or with Spam off takes them back to the Inbox.", table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("Spam", table: "ShortcutActions"), default: true)
    public var spam: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$spam, .equalTo, true) {
            Summary("Report \(\.$threads) as spam", table: "ShortcutFlow") { \.$spam }
        } otherwise: {
            Summary("Move \(\.$threads) out of Spam", table: "ShortcutFlow") { \.$spam }
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let undo = try await Catalog(host: host).perform(
            spam ? .reportSpam : .moveToInbox, onThreads: threads.map(\.id))
        await offerUndo(of: [undo], named: Self.title, host: host)
        return .result(value: threads)
    }
}

/// Deletes the conversations' messages in Trash for good, after asking unless told not to. Nothing undoes it.
public struct DeleteForeverIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Delete Conversations Forever", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Deletes the messages of conversations that are in Trash for good. Messages anywhere else stay.",
            table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutActions"))
    public var threads: [ThreadEntity]

    /// Off for an automation that runs on its own, where nobody is there to answer.
    @Parameter(
        title: LocalizedStringResource("Ask Before Deleting", table: "ShortcutFlow"),
        description: LocalizedStringResource(
            "Turn off for an automation that runs on its own, so it doesn't wait for an answer.",
            table: "ShortcutFlow"),
        default: true)
    public var asks: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$threads) forever", table: "ShortcutActions") { \.$asks }
    }

    public func perform() async throws -> some IntentResult {
        guard !threads.isEmpty else { return .result() }
        if asks { try await confirm() }
        try await Catalog(host: host).perform(.deleteForever, onThreads: threads.map(\.id))
        return .result()
    }

    private func confirm() async throws {
        try await requestConfirmation(
            actionName: .custom(
                acceptLabel: LocalizedStringResource("Delete Forever", table: "ShortcutActions"),
                acceptAlternatives: [], denyLabel: LocalizedStringResource("Cancel", table: "ShortcutActions"),
                denyAlternatives: [],
                destructive: true),
            dialog: IntentDialog(
                LocalizedStringResource(
                    "Delete these conversations' messages in Trash forever? This can't be undone.",
                    table: "ShortcutActions")))
    }
}

extension Catalog {
    /// Moves each thread from the mailbox it's in to `destination`. Returns what undoes each move.
    func move(_ identifiers: [String], to destination: MoveDestination) async throws -> [MailCommands.Undo] {
        // An automation's Find can come up empty; doing nothing then is a success, so the shortcut runs on.
        guard !identifiers.isEmpty else { return [] }
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
