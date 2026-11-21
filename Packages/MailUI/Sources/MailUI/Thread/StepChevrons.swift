import MailCore
import UIKit

/// The up and down chevrons of a reader pushed in a narrow window, to the conversation above and below in the list,
/// as Mail has them, dimmed at either end. They point up and down in every language, so they don't mirror.
///
/// They are their own observation scope: this view's `updateProperties` reads only whether each way leads anywhere,
/// through `steps`, so a row that comes or goes in the list dims them without running the reader's, which lays out
/// the whole conversation. It takes no room and shows nothing; the items sit in the reader's bar.
final class StepChevrons: UIView {
    let up = UIBarButtonItem()
    let down = UIBarButtonItem()
    /// Where they lead; `nil` beside the list, where they don't show.
    var steps: ConversationSteps? {
        didSet { setNeedsUpdateProperties() }
    }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for (item, step, command, symbol) in [
            (up, WindowNavigation.Step.previous, MailCommand.previousThread, "chevron.up"),
            (down, .next, .nextThread, "chevron.down"),
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Dims a chevron that leads nowhere now. It reads the list's rows through `steps`, so a row that comes or goes
    /// updates them; what the window's navigation changes calls `setNeedsUpdateProperties` (`MailScreens`).
    override func updateProperties() {
        super.updateProperties()
        up.isEnabled = steps?.leads(.previous) == true
        down.isEnabled = steps?.leads(.next) == true
    }
}
