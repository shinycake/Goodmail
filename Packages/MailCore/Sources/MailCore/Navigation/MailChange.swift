/// What the reader asked of some conversations in a window: an action, a move, a snooze, or blocking their sender.
/// The window hears of each as it is asked, before it applies, and decides from it alone whether its reader moves:
/// what sync, other devices or other windows change only ever changes rows (R6).
public struct MailChange: Equatable, Sendable {
    public enum Request: Equatable, Sendable {
        case action(ThreadAction)
        case move(MoveDestination, from: Mailbox)
        case snooze
        case unsnooze
        /// Block Sender, whose rule then takes the conversations to Trash. Asked only of the conversations the rule
        /// trashes: one whose newest mail from someone else is from another person stays where it is.
        case block
    }

    public let request: Request
    public let threads: [ThreadSummary.ID]

    public init(_ request: Request, on threads: [ThreadSummary.ID]) {
        self.request = request
        self.threads = threads
    }
}
