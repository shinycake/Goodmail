import MailCore
import Testing
import UIKit

@testable import MailUI

/// Which screen a command reaches: a presented screen alone, else the thread before its list before the mailboxes.
@Suite("Command routing")
@MainActor
struct CommandRoutingTests {
    private let mailboxes = StubScreen(answering: [.newMessage])
    private let list = StubScreen(answering: [.newMessage, .getMail, .search])
    private let thread = StubScreen(answering: [.reply, .archive, .newMessage])

    @Test("The window offers only what the screens on show answer")
    func offersWhatScreensAnswer() {
        let root = split(folded: false)
        let offered = Set(keyCommands(in: root).compactMap { MailCommand($0) })
        #expect(offered == [.newMessage, .getMail, .search, .reply, .archive])
    }

    @Test("Side by side, the thread answers before its list and the mailboxes")
    func threadFirstSideBySide() {
        perform(.newMessage, in: split(folded: false))
        #expect(thread.performed == [.newMessage])
        #expect(list.performed.isEmpty)
        #expect(mailboxes.performed.isEmpty)
    }

    @Test("A shortcut the thread doesn't answer goes to the list")
    func fallsThroughToTheList() {
        perform(.getMail, in: split(folded: false))
        #expect(list.performed == [.getMail])
        #expect(thread.performed.isEmpty)
    }

    @Test("Collapsed, only the top of the stack answers")
    func collapsedTopOnly() {
        let stack = UINavigationController(rootViewController: list)
        stack.pushViewController(thread, animated: false)
        let root = StubSplit(folded: true)
        root.setViewController(stack, for: .compact)
        perform(.getMail, in: root)
        #expect(list.performed.isEmpty, "the list under the thread isn't on show")
        perform(.reply, in: root)
        #expect(thread.performed == [.reply])
    }

    @Test("A reader pushed on a narrow stack offers Next and Previous, from the mail screens around it")
    func pushedReaderOffersBoth() {
        let stack = UINavigationController(rootViewController: list)
        stack.pushViewController(thread, animated: false)
        var taken: [WindowNavigation.Step] = []
        let root = StepsSplit(steps: ConversationSteps(leads: { _ in true }, take: { taken.append($0) }))
        root.setViewController(stack, for: .compact)
        let offered = Set(keyCommands(in: root).compactMap { MailCommand($0) })
        #expect(offered.isSuperset(of: [.nextThread, .previousThread, .reply]))
        perform(.nextThread, in: root)
        perform(.previousThread, in: root)
        #expect(taken == [.next, .previous])
        perform(.reply, in: root)
        #expect(thread.performed == [.reply], "the reader still answers first")
    }

    @Test("At an end, the way that leads nowhere is dimmed")
    func endDimsTheStep() {
        let root = StepsSplit(steps: ConversationSteps(leads: { $0 == .next }, take: { _ in }))
        root.setViewController(UINavigationController(rootViewController: thread), for: .compact)
        guard case .unavailable = CommandRouting.answer(to: .previousThread, in: root) else {
            Issue.record("Previous Conversation should be dimmed at the top")
            return
        }
        guard case .ready = CommandRouting.answer(to: .nextThread, in: root) else {
            Issue.record("Next Conversation should be ready")
            return
        }
    }

    @Test("A presented screen hides the screens behind it")
    func presentedAnswersAlone() {
        let composer = StubScreen(answering: [.send])
        let root = StubPresenter(presenting: composer)
        root.addChild(split(folded: false))
        #expect(keyCommands(in: root).compactMap { MailCommand($0) } == [.send])
        perform(.reply, in: root)
        #expect(thread.performed.isEmpty)
        perform(.send, in: root)
        #expect(composer.performed == [.send])
    }

    @Test("A screen being dismissed no longer answers")
    func dismissingScreenSteppedOver() {
        let composer = StubScreen(answering: [.send], dismissing: true)
        let root = StubPresenter(presenting: composer)
        root.addChild(split(folded: false))
        perform(.reply, in: root)
        #expect(thread.performed == [.reply])
        #expect(composer.performed.isEmpty)
    }

    @Test("A screen that has the command but can't do it now stops the search, so the menu dims it")
    func unavailableStops() {
        let busy = StubScreen(answering: [], unavailable: [.getMail])
        let stack = UINavigationController(rootViewController: list)
        let root = StubSplit(folded: false)
        root.setViewController(stack, for: .supplementary)
        root.setViewController(UINavigationController(rootViewController: busy), for: .secondary)
        guard case .unavailable = CommandRouting.answer(to: .getMail, in: root) else {
            Issue.record("Get Mail should be dimmed")
            return
        }
        #expect(list.performed.isEmpty)
    }

    @Test("A command no screen has, and one without keys, offers no key command")
    func keylessAndUnansweredLeftOut() {
        let screen = StubScreen(answering: [.pin, .reply])
        #expect(keyCommands(in: screen).compactMap { MailCommand($0) } == [.reply])
    }

    @Test("The answer's title names the key command", arguments: [nil, "Reply to Dana"] as [String?])
    func keyCommandTitle(_ title: String?) {
        let screen = StubScreen(answering: [.reply], title: title)
        #expect(keyCommands(in: screen).map(\.title) == [title ?? MailCommand.reply.title])
    }

    @Test("Every command has a name for the menu bar and the list Command shows", arguments: MailCommand.allCases)
    func named(_ command: MailCommand) {
        #expect(!command.title.isEmpty)
    }

    private func keyCommands(in root: UIViewController) -> [UIKeyCommand] {
        CommandRouting.keyCommands(action: #selector(UIResponder.copy(_:))) { CommandRouting.answer(to: $0, in: root) }
    }

    private func split(folded: Bool) -> UISplitViewController {
        let split = StubSplit(folded: folded)
        split.setViewController(UINavigationController(rootViewController: mailboxes), for: .primary)
        split.setViewController(UINavigationController(rootViewController: list), for: .supplementary)
        split.setViewController(UINavigationController(rootViewController: thread), for: .secondary)
        return split
    }

    private func perform(_ command: MailCommand, in root: UIViewController) {
        if case .ready(let perform, _, _) = CommandRouting.answer(to: command, in: root) { perform() }
    }
}

/// A screen that answers `answering`, records what it performed, and has `unavailable` but can't do it now.
private final class StubScreen: UIViewController, CommandScreen {
    private let answering: Set<MailCommand>
    private let unavailable: Set<MailCommand>
    private let dismissing: Bool
    private let answerTitle: String?
    private(set) var performed: [MailCommand] = []

    init(
        answering: Set<MailCommand>, unavailable: Set<MailCommand> = [], dismissing: Bool = false,
        title: String? = nil
    ) {
        self.answering = answering
        self.unavailable = unavailable
        self.dismissing = dismissing
        self.answerTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override var isBeingDismissed: Bool { dismissing }

    func answer(to command: MailCommand) -> CommandAnswer {
        if unavailable.contains(command) { return .unavailable }
        guard answering.contains(command) else { return .notHere }
        return .ready(perform: { [weak self] in self?.performed.append(command) }, title: answerTitle)
    }
}

/// A split view that reports itself collapsed or not without a window.
private final class StubSplit: UISplitViewController {
    private let folded: Bool

    init(folded: Bool) {
        self.folded = folded
        super.init(style: .tripleColumn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override var isCollapsed: Bool { folded }
}

/// A collapsed split view that offers Next and Previous Conversation through `steps`, as the window's mail screens do.
private final class StepsSplit: UISplitViewController, CommandScreen {
    private let steps: ConversationSteps

    init(steps: ConversationSteps) {
        self.steps = steps
        super.init(style: .tripleColumn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override var isCollapsed: Bool { true }

    func answer(to command: MailCommand) -> CommandAnswer {
        steps.answer(to: command)
    }
}

/// A root that shows `presenting` over its children without a window.
private final class StubPresenter: UIViewController {
    private let presenting: UIViewController

    init(presenting: UIViewController) {
        self.presenting = presenting
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override var presentedViewController: UIViewController? { presenting }
}
