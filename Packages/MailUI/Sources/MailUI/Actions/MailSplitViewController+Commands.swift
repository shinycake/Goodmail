public import MailCore

/// The window's mail screens answer Next and Previous Conversation themselves, after the screens on show, so the keys
/// work in every arrangement: beside the list, and in a narrow stack whose reader covers it.
extension MailSplitViewController: CommandScreen {
    public func answer(to command: MailCommand) -> CommandAnswer {
        steps?.answer(to: command) ?? .notHere
    }
}
