/// Block Sender (ADR-038): a rule like any other, so it shows in Settings, follows the reader to their other devices
/// and runs wherever rules run. It sends the sender's mail to Trash and is first, stopping the others, so no later rule
/// stars it or alerts for it.
extension MailRule {
    /// Block Sender's rule for `sender`, called `name`.
    public static func blocking(_ sender: SenderAddress, named name: String) -> MailRule {
        MailRule(
            name: name, condition: .text(.senderAddress, .equals(sender.address)), actions: [.trash],
            stopsOtherRules: true)
    }

    /// Whom the rule blocks, while it is Block Sender's rule as Block Sender wrote it. A rule changed in Settings to
    /// do something else is the reader's own rule, and blocks no one.
    public var blockedSender: SenderAddress? {
        guard case .text(.senderAddress, .equals(let address)) = condition, actions == [.trash], stopsOtherRules,
            let sender = SenderAddress(address)
        else { return nil }
        return sender
    }
}

extension RuleBook {
    /// `rules` with `sender` blocked: Block Sender's rule for them first and on, keeping the ID of one already there,
    /// so blocking twice writes one rule.
    public static func blocking(_ sender: SenderAddress, named name: String, in rules: [MailRule]) -> [MailRule] {
        var block = MailRule.blocking(sender, named: name)
        if let earlier = rules.first(where: { $0.blockedSender == sender }) {
            block.id = earlier.id
            block.name = earlier.name
        }
        return [block] + rules.filter { $0.blockedSender != sender }
    }
}
