import MailCore
import UIKit

/// Apply Rules, the VIP command and Block Sender, asked in this window and done by the app's `SenderRules`. Block
/// Sender goes through the window's actions, as Archive does, so the window hears first which conversations it takes
/// away and moves its reader at once (R7).
extension MailActions {
    /// What Apply Rules, the VIP command and Block Sender do to `threads`, from `sender` when they are all from one
    /// person other than the reader; `nil` for any other command. Without such a sender, the sender's commands are
    /// dimmed. `conversationsFrom` is who the conversations are from, the sender of their newest mail from someone
    /// else, which Block Sender's rule judges them by.
    func senderAnswer(
        to command: MailCommand, for threads: [ThreadSummary.ID], from sender: SenderAddress?,
        conversationsFrom: SenderAddress?, with rules: SenderRules
    ) -> CommandAnswer? {
        switch command {
        case .applyRules:
            guard !threads.isEmpty else { return .unavailable }
            return .ready(perform: { rules.applyRules(to: threads) })
        case .vipSender:
            guard let sender else { return .unavailable }
            let isVIP = !rules.vips.contains(sender)
            return .ready(perform: { rules.setVIP(sender, isVIP) }, title: SenderRules.vipTitle(isVIP))
        case .blockSender:
            guard let sender else { return .unavailable }
            let trashed = sender == conversationsFrom ? threads : []
            return .ready(perform: { [self] in block(sender, then: threads, trashing: trashed, with: rules) })
        default:
            return nil
        }
    }

    /// The same commands as a section of a context menu, leaving out what the menu bar would dim.
    func senderMenuSection(
        for threads: [ThreadSummary.ID], from sender: SenderAddress?, conversationsFrom: SenderAddress?,
        with rules: SenderRules
    ) -> UIMenu {
        let items = SenderRules.commands.compactMap { command -> UIAction? in
            guard
                case .ready(let perform, let title, _) = senderAnswer(
                    to: command, for: threads, from: sender, conversationsFrom: conversationsFrom, with: rules)
            else { return nil }
            return UIAction(
                title: title ?? command.title, image: UIImage(systemName: command.senderSymbol),
                attributes: command == .blockSender ? .destructive : []
            ) { _ in perform() }
        }
        return UIMenu(options: .displayInline, children: items)
    }

    /// Block Sender: has `rules` block `sender` and run on `threads`. Its rule takes to Trash, whole, only the ones
    /// `trashing` names, whose newest mail from someone else is from the sender; the window hears of those at once,
    /// and of none when there are none, as when the person blocked only wrote earlier in the conversation.
    func block(
        _ sender: SenderAddress, then threads: [ThreadSummary.ID], trashing: [ThreadSummary.ID],
        with rules: SenderRules
    ) {
        if !trashing.isEmpty { changed?(MailChange(.block, on: trashing)) }
        rules.block(sender, then: threads)
    }
}
