import MailCore
import UIKit

/// The up and down chevrons of a reader pushed in a narrow window, to the conversation above and below in the list,
/// as Mail has them, dimmed at either end. They point up and down in every language, so they don't mirror.
extension ThreadViewController {
    func configureStepItems() {
        for (item, step, command, symbol) in [
            (previousItem, WindowNavigation.Step.previous, MailCommand.previousThread, "chevron.up"),
            (nextItem, .next, .nextThread, "chevron.down"),
        ] {
            // The title is the button's name for VoiceOver and Large Content, and the menu's when the bar overflows.
            item.title = command.title
            item.image = UIImage(systemName: symbol)
            item.accessibilityIdentifier = step == .next ? "thread.next" : "thread.previous"
            item.primaryAction = UIAction(title: command.title, image: item.image) { [weak self] _ in
                self?.steps?.take(step)
            }
        }
    }

    /// Dims a chevron that leads nowhere now. Called in `updateProperties`, which reads the list's rows through
    /// `steps`, so a row that comes or goes updates them too.
    func updateStepItems() {
        previousItem.isEnabled = steps?.leads(.previous) == true
        nextItem.isEnabled = steps?.leads(.next) == true
    }
}
