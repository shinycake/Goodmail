public import MailCore

/// Next and Previous Conversation as the window offers them, to the menu bar and the keys (`MailSplitViewController`)
/// and to a narrow window's reader as its chevrons: whether each way leads anywhere now, and going there.
@MainActor
public struct ConversationSteps {
    /// Whether `step` reaches a conversation now.
    public let leads: (WindowNavigation.Step) -> Bool
    /// Reads the conversation `step` reaches.
    public let take: (WindowNavigation.Step) -> Void

    public init(
        leads: @escaping (WindowNavigation.Step) -> Bool, take: @escaping (WindowNavigation.Step) -> Void
    ) {
        self.leads = leads
        self.take = take
    }

    /// The step a command takes, or `nil` for any other command.
    static func step(for command: MailCommand) -> WindowNavigation.Step? {
        switch command {
        case .nextThread: .next
        case .previousThread: .previous
        default: nil
        }
    }

    /// The answer to `command`, Next or Previous Conversation: ready while it leads somewhere, dimmed at the ends.
    func answer(to command: MailCommand) -> CommandAnswer {
        guard let step = Self.step(for: command) else { return .notHere }
        guard leads(step) else { return .unavailable }
        return .ready(perform: { take(step) })
    }
}
