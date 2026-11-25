public import MailCore
import UIKit

/// The composer sends, attaches, shows Cc and Bcc and formats from the menu bar and the keyboard, as its buttons do.
/// Formatting waits for the body to have the keyboard, and the menu checks the styles and lists the selection has.
extension ComposeViewController: CommandScreen {
    /// Once the message ended, its commands stay dimmed while its card leaves, rather than falling to the screens
    /// behind it.
    public func answer(to command: MailCommand) -> CommandAnswer {
        let answer = writingAnswer(to: command)
        guard !viewModel.isWriting else { return answer }
        if case .notHere = answer { return .notHere }
        return .unavailable
    }

    private func writingAnswer(to command: MailCommand) -> CommandAnswer {
        switch command {
        case .send: return .offering(viewModel.canSend ? { [weak self] in self?.send() } : nil)
        case .sendLater: return .offering(viewModel.canSend ? { [weak self] in self?.pickSendTime() } : nil)
        case .attachFiles: return .ready(perform: { [weak self] in self?.picker.choose(.file) })
        case .showCopyFields:
            guard copyFields == .folded else { return .unavailable }
            return .ready(perform: { [weak self] in
                self?.showCopyFields()
                self?.ccField.becomeFirstResponder()
            })
        case .addLink: return formatting { _ in { [weak self] in self?.askForLink() } }
        case .strikethrough: return format(.toggle(.strikethrough)) { $0.styles.contains(.strikethrough) }
        case .bulletedList: return format(.block(.bulleted)) { $0.block == .bulleted }
        case .numberedList: return format(.block(.numbered)) { $0.block == .numbered }
        case .increaseQuoteLevel:
            return formatting { formatting in
                formatting.quoteLevel < RichText.QuoteLevel.deepest
                    ? { [weak self] in self?.applyFormatting(.quote(.increase)) } : nil
            }
        case .decreaseQuoteLevel:
            return formatting { formatting in
                formatting.quoteLevel > RichText.QuoteLevel.none
                    ? { [weak self] in self?.applyFormatting(.quote(.decrease)) } : nil
            }
        // Zoom In and Zoom Out hold Format > Font's keys for Bigger and Smaller, which they do here.
        case .zoomIn: return formatting { _ in { [weak self] in self?.bodyView.increaseSize(nil) } }
        case .zoomOut: return formatting { _ in { [weak self] in self?.bodyView.decreaseSize(nil) } }
        default: return .notHere
        }
    }

    /// `change`, checked in the menu while `isOn` the selection.
    private func format(_ change: FormattingCommand, isOn: (Formatting) -> Bool) -> CommandAnswer {
        guard bodyView.isFirstResponder else { return .unavailable }
        return .ready(perform: { [weak self] in self?.applyFormatting(change) }, isOn: isOn(currentFormatting))
    }

    /// What `perform` makes of the selection's formatting, while the body has the keyboard.
    private func formatting(_ perform: (Formatting) -> (() -> Void)?) -> CommandAnswer {
        guard bodyView.isFirstResponder else { return .unavailable }
        return .offering(perform(currentFormatting))
    }
}
