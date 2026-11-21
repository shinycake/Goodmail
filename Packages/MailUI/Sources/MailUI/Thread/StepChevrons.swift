import MailCore
import Observation
import UIKit

/// The up and down chevrons of a reader pushed in a narrow window, to the conversation above and below in the list,
/// as Mail has them, dimmed at either end. They point up and down in every language, so they don't mirror.
///
/// They follow where they lead on their own, by an observation of `steps` alone, so a row that comes or goes in the
/// list dims them without the reader's `updateProperties`, which lays out the whole conversation, running again.
/// What the window's navigation changes, which isn't observed, comes as `refresh()` (`MailScreens`).
final class StepChevrons {
    let up = UIBarButtonItem()
    let down = UIBarButtonItem()
    /// Where they lead; `nil` beside the list, where they don't show.
    var steps: ConversationSteps? {
        didSet { follow() }
    }
    /// Follows `leads` while there are steps; leaving the reader cancels it.
    private var following: Task<Void, Never>?

    /// Whether each way leads anywhere now.
    private nonisolated struct Leads: Equatable, Sendable {
        var previous = false
        var next = false
    }

    init() {
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

    isolated deinit {
        following?.cancel()
    }

    /// Dims a chevron that leads nowhere now.
    func refresh() {
        show(leads)
    }

    private var leads: Leads {
        Leads(previous: steps?.leads(.previous) == true, next: steps?.leads(.next) == true)
    }

    private func show(_ leads: Leads) {
        up.isEnabled = leads.previous
        down.isEnabled = leads.next
    }

    /// Follows the list's rows through `steps`, from now, for as long as there are steps.
    private func follow() {
        following?.cancel()
        following = nil
        refresh()
        guard steps != nil else { return }
        following = Task { [weak self] in
            for await leads in Observations({ [weak self] in self?.leads ?? Leads() }) {
                self?.show(leads)
            }
        }
    }
}
