public import Foundation

/// The iPhone's side of the link (ADR-022): it keeps the watch's snapshot current and runs the commands the watch
/// sends, each once, however often it arrives.
public actor WristServer {
    /// How many run commands the iPhone remembers. Far more than the watch can have waiting.
    static let appliedLimit = 64

    private let execute: @Sendable (WristCommand) async throws -> Void
    private let send: @Sendable (WristSnapshot) async -> Void
    private let remember: @Sendable ([UUID]) -> Void
    /// The newest Inbox, before `applied` is added.
    private var latest: WristSnapshot?
    /// The commands run, oldest first.
    private var applied: [UUID]

    /// - Parameters:
    ///   - applied: the commands already run, as `remember` last stored them.
    ///   - execute: runs a command's change on the mail.
    ///   - send: hands a snapshot to the watch.
    ///   - remember: stores the commands run, so a command delivered again after a relaunch still runs once.
    public init(
        applied: [UUID], execute: @escaping @Sendable (WristCommand) async throws -> Void,
        send: @escaping @Sendable (WristSnapshot) async -> Void, remember: @escaping @Sendable ([UUID]) -> Void
    ) {
        self.applied = applied
        self.execute = execute
        self.send = send
        self.remember = remember
    }

    /// The Inbox changed.
    public func inboxChanged(_ snapshot: WristSnapshot) async {
        latest = snapshot
        await sendLatest()
    }

    /// Runs a command the watch sent, unless it ran already. A command that fails still counts as run, so the watch
    /// stops showing its effect and shows the mail as it is.
    /// It throws what running the command threw.
    public func received(_ command: WristCommand) async throws {
        guard !applied.contains(command.id) else { return }
        applied = Array((applied + [command.id]).suffix(Self.appliedLimit))
        remember(applied)
        let outcome = await Result { try await execute(command) }
        await sendLatest()
        try outcome.get()
    }

    private func sendLatest() async {
        guard var snapshot = latest else { return }
        snapshot.applied = applied
        await send(snapshot)
    }
}
