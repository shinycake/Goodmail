import Testing
import UIKit

@testable import MailUI

/// Which screen a shortcut reaches: a presented screen alone, else the thread before its list before the mailboxes.
@Suite("Keyboard shortcut routing")
@MainActor
struct KeyboardShortcutRoutingTests {
    private let mailboxes = StubScreen(answering: [.newMessage])
    private let list = StubScreen(answering: [.newMessage, .getMail, .search])
    private let thread = StubScreen(answering: [.reply, .archive, .newMessage])

    @Test("The window offers only what the screens on show answer")
    func offersWhatScreensAnswer() {
        let root = split(folded: false)
        let offered = Set(KeyboardShortcuts.commands(in: root, action: #selector(UIResponder.copy(_:))).map(\.input))
        let expected = Set(([.newMessage, .getMail, .search, .reply, .archive] as [KeyboardShortcut]).map(\.input))
        #expect(offered == expected)
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

    @Test("A presented screen hides the screens behind it")
    func presentedAnswersAlone() {
        let composer = StubScreen(answering: [.send])
        let root = StubPresenter(presenting: composer)
        root.addChild(split(folded: false))
        #expect(
            KeyboardShortcuts.commands(in: root, action: #selector(UIResponder.copy(_:))).map(\.input) == [
                KeyboardShortcut.send.input
            ])
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

    private func split(folded: Bool) -> UISplitViewController {
        let split = StubSplit(folded: folded)
        split.setViewController(UINavigationController(rootViewController: mailboxes), for: .primary)
        split.setViewController(UINavigationController(rootViewController: list), for: .supplementary)
        split.setViewController(UINavigationController(rootViewController: thread), for: .secondary)
        return split
    }

    private func perform(_ shortcut: KeyboardShortcut, in root: UIViewController) {
        KeyboardShortcuts.action(for: shortcut, in: root)?()
    }
}

/// A screen that answers `answering` and records what it performed.
private final class StubScreen: UIViewController, KeyboardShortcutScreen {
    private let answering: Set<KeyboardShortcut>
    private let dismissing: Bool
    private(set) var performed: [KeyboardShortcut] = []

    init(answering: Set<KeyboardShortcut>, dismissing: Bool = false) {
        self.answering = answering
        self.dismissing = dismissing
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override var isBeingDismissed: Bool { dismissing }

    func action(for shortcut: KeyboardShortcut) -> (() -> Void)? {
        guard answering.contains(shortcut) else { return nil }
        return { [weak self] in self?.performed.append(shortcut) }
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
