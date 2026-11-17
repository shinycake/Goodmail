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
    /// The commands that failed since launch, oldest first; a subset of `applied`.
    private var failed: [UUID] = []

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

    /// The owner flipped "Mail Without iPhone" (ADR-023): the watch hears it at once, with the Inbox it has, made
    /// again at `now`, rather than with the next change to the Inbox.
    public func independenceChanged(to independence: WristIndependence, at now: Date) async {
        guard var snapshot = latest, snapshot.extras != nil else { return }
        snapshot.extras?.independence = independence
        snapshot.madeAt = now
        latest = snapshot
        await sendLatest()
    }

    /// Runs a command the watch sent, unless it ran already. It throws what running the command threw.
    ///
    /// A command that ran is confirmed with the next Inbox change, which carries its effect; confirming it sooner,
    /// with the Inbox from before, would show the swiped row again for a moment. A command that fails changes nothing,
    /// so it is confirmed at once, and the watch shows the mail as it is.
    public func received(_ command: WristCommand) async throws {
        guard !applied.contains(command.id) else { return }
        applied = Array((applied + [command.id]).suffix(Self.appliedLimit))
        remember(applied)
        do {
            try await execute(command)
        } catch {
            failed = Array((failed + [command.id]).suffix(Self.appliedLimit))
            await sendLatest()
            throw error
        }
    }

    private func sendLatest() async {
        guard var snapshot = latest else { return }
        snapshot.applied = applied
        snapshot.failed = failed.filter(applied.contains)
        await send(snapshot)
    }
}
