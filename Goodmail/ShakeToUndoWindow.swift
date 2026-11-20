import MailCore
import MailUI
import UIKit

/// A window that undoes the last mail action when shaken, from any screen, and performs the keyboard shortcuts and
/// menu bar commands of the screens it shows, and its own (ADR-034).
///
/// A shake goes to the first responder and travels up the responder chain to the window, or straight to the window
/// when nothing is first responder, so catching it here needs no screen to hold first responder. A screen that did
/// would make UIKit reload the input views each time a menu opens, which raises the keyboard with no field focused.
/// A text field or view that is editing still takes the shake first, for its own Undo Typing. Commands reach the window
/// the same way, so each window answers its own.
final class ShakeToUndoWindow: UIWindow {
    private let undo: () -> Void
    /// What the window itself does for a command no screen has, as New Window.
    var windowAnswer: (MailCommand) -> CommandAnswer = { _ in .notHere }
    /// How the window is driven, which its screens read from their trait collection.
    let interactionStyle: InteractionStyle

    init(windowScene: UIWindowScene, undo: @escaping () -> Void) {
        self.undo = undo
        // The one place a window's interaction style is decided, at the app's edge: Mac windows are driven by pointer
        // and keyboard, all others by touch. Screens read it from their trait collection.
        interactionStyle = InteractionStyle(idiom: windowScene.traitCollection.userInterfaceIdiom)
        super.init(windowScene: windowScene)
        traitOverrides.interactionStyle = interactionStyle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Without a menu bar, the window offers the screens' keyed commands as key commands of its own, which reach it
    /// from any first responder, or straight away when there is none, for the same reason a shake does. Each screen
    /// says which commands it can do now (`CommandRouting`).
    override var keyCommands: [UIKeyCommand]? {
        guard !MailMenus.inMenuBar else { return super.keyCommands }
        return (super.keyCommands ?? [])
            + CommandRouting.keyCommands(action: #selector(performCommand(_:))) {
                CommandRouting.answer(to: $0, in: rootViewController)
            }
    }

    /// The menu bar's commands are enabled only while this window can do them, and so are the system items that carry
    /// Apple Mail's keys for one of them, as Find and Replace for Search Mail.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(performCommand(_:)) {
            return (sender as? UICommand).flatMap(MailCommand.init).flatMap(perform(for:)) != nil
        }
        // Without a menu bar, the command has the keys itself, and the system item isn't there to answer.
        if let item = SystemMenuItem(action: action) {
            return MailMenus.inMenuBar && item.command.flatMap(perform(for:)) != nil
        }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Titles and checks a command's menu item as the screen that would do it says.
    override func validate(_ command: UICommand) {
        super.validate(command)
        guard let mailCommand = MailCommand(command) else { return }
        guard case .ready(_, let title, let isOn) = answer(to: mailCommand) else {
            command.title = mailCommand.title
            command.state = .off
            return
        }
        command.title = title ?? mailCommand.title
        command.state = isOn ? .on : .off
    }

    /// In the menu bar, Find and Replace holds ⌥⌘F, Apple Mail's Search Mail, so it searches the mail while no text
    /// has the keyboard. A text view that has it answers first, being ahead of the window in the responder chain.
    override func findAndReplace(_ sender: Any?) {
        performSystemItem(.findAndReplace)
    }

    /// File > Print prints the conversation on show.
    override func printContent(_ sender: Any?) {
        performSystemItem(.print)
    }

    /// Find, Find Next and Find Previous search the open conversation; ⌘F and ⌘G are Apple's keys for them.
    override func find(_ sender: Any?) {
        performSystemItem(.find)
    }

    override func findNext(_ sender: Any?) {
        performSystemItem(.findNext)
    }

    override func findPrevious(_ sender: Any?) {
        performSystemItem(.findPrevious)
    }

    /// Format > Font > Bigger and Smaller zoom the reader while no text view has the keyboard and takes them as its
    /// font size.
    override func increaseSize(_ sender: Any?) {
        performSystemItem(.biggerText)
    }

    override func decreaseSize(_ sender: Any?) {
        performSystemItem(.smallerText)
    }

    @objc func performCommand(_ command: UICommand) {
        MailCommand(command).flatMap(perform(for:))?()
    }

    private func performSystemItem(_ item: SystemMenuItem) {
        item.command.flatMap(perform(for:))?()
    }

    /// What `command` does here: on the frontmost screen that has it, else on the window.
    private func answer(to command: MailCommand) -> CommandAnswer {
        let answer = CommandRouting.answer(to: command, in: rootViewController)
        guard case .notHere = answer else { return answer }
        return windowAnswer(command)
    }

    private func perform(for command: MailCommand) -> (() -> Void)? {
        guard case .ready(let perform, _, _) = answer(to: command) else { return nil }
        return perform
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return super.motionEnded(motion, with: event) }
        undo()
    }
}
