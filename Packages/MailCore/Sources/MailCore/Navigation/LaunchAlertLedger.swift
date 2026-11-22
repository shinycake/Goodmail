/// The failed sends the app offers to edit, retry or delete, each once a launch, in whichever window is in front.
/// Kept for the whole app, so a second window, or one opened later, doesn't offer them again.
public struct LaunchAlertLedger<Message: Identifiable & Sendable>: Sendable where Message.ID: Sendable {
    /// The failed sends as the outbox last listed them.
    private var failed: [Message] = []
    /// The ones offered already this launch.
    private var shown: Set<Message.ID> = []

    public init() {}

    /// The outbox's failed sends now.
    public mutating func failedNow(_ messages: [Message]) {
        failed = messages
    }

    /// The first failed send not offered yet this launch.
    public var nextFailure: Message? {
        failed.first { !shown.contains($0.id) }
    }

    /// A window offered the failed send `id`.
    public mutating func showed(_ id: Message.ID) {
        shown.insert(id)
    }
}
