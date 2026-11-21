public import MailCore
public import UIKit

/// A viewer window's screens, kept showing what its navigation says (`WindowState.stack` and `.columns`): the split
/// view's columns when the window is wide, its one stack when it is narrow. Each change is made in one go, and a screen
/// whose entry is unchanged stays the same screen, so the list keeps its scroll, search and Select mode, and the reader
/// its place, its layout and anything typed, across every transition that leaves them be. Back on the stack is
/// reported as `.back`, for the navigation to follow.
///
/// The list and the reader are one each, whichever arrangement shows them: as the window changes width they move
/// between the columns and the stack (D8), placed in the arrangement coming before the split view shows it
/// (`show(_:row:_:in:)` with `.resized`, from its collapse and expand hooks). Only the mailboxes differ, a sidebar
/// beside the columns and a list at the bottom of the stack.
///
/// It tells the list on show which conversation is read, and the sidebar which list is shown, so neither keeps its own
/// idea of either (R11).
public final class MailScreens: NSObject {
    /// What makes each screen.
    public struct Makers {
        public var mailboxes: (MailboxesViewController.Style) -> MailboxesViewController
        public var list: (WindowState.List) -> UIViewController
        /// A reader for the conversation from its row, or `nil` when it can't be read, as one whose account is gone.
        public var reader: (Reading, ThreadSummary) -> ThreadViewController?

        public init(
            mailboxes: @escaping (MailboxesViewController.Style) -> MailboxesViewController,
            list: @escaping (WindowState.List) -> UIViewController,
            reader: @escaping (Reading, ThreadSummary) -> ThreadViewController?
        ) {
            self.mailboxes = mailboxes
            self.list = list
            self.reader = reader
        }
    }

    /// A screen made for `entry`.
    private struct Made<Entry: Equatable, Screen: UIViewController> {
        let entry: Entry
        let screen: Screen
    }

    /// Why the screens show what they show.
    public enum Showing: Equatable, Sendable {
        /// The window moved by itself, after an action or Undo: VoiceOver goes to the new reader, or to the list.
        case announced
        /// The reader moved it, by a tap, a click or keys, which VoiceOver follows on its own.
        case quiet
        /// Nothing moved: the window changed width, and the arrangement it shows now takes the screens, without
        /// animating or bringing a column forward.
        case resized
    }

    public let split: MailSplitViewController
    private let makers: Makers
    /// Next and Previous Conversation, which a reader pushed on the stack offers as chevrons in its bar.
    private let steps: ConversationSteps?
    /// Back on the stack, by its button or edge swipe.
    public var wentBack: ((WindowNavigation.Back) -> Void)?
    /// The arrangement shown last, which holds the list and the reader.
    public private(set) var arrangement: WindowNavigation.Arrangement

    private let sidebarColumn = UINavigationController()
    private let listColumn = UINavigationController()
    private let detailColumn = UINavigationController()
    private let stack = MailStackController()
    /// The mailboxes as each arrangement shows them, made when it first shows.
    private var sidebar: MailboxesViewController?
    private var stackMailboxes: MailboxesViewController?
    /// The one list and the one reader, in whichever arrangement shows.
    private var listMade: Made<WindowState.List, UIViewController>?
    private var readerMade: Made<Reading, ThreadViewController>?
    /// The stack's screens as last set, so a change the stack made itself is told from one made here.
    private var stackScreens: [UIViewController] = []

    /// Builds `arrangement` for `state`, in `split`, a reader pushed on the stack offering `steps`. `row` is the
    /// conversation read's, when the window has it. A reader that can't be made leaves the list showing, and
    /// `readable` says so.
    public init(
        _ state: WindowState, row: ThreadSummary?, in split: MailSplitViewController,
        arrangement: WindowNavigation.Arrangement, steps: ConversationSteps? = nil, making makers: Makers
    ) {
        self.split = split
        self.makers = makers
        self.steps = steps
        self.arrangement = arrangement
        super.init()
        stack.delegate = self
        split.setViewController(sidebarColumn, for: .primary)
        split.setViewController(listColumn, for: .supplementary)
        split.setViewController(detailColumn, for: .secondary)
        split.setViewController(stack, for: .compact)
        readable = show(state, row: row, .resized, in: arrangement)
    }

    /// Whether the reader the screens were built with could be made.
    public private(set) var readable = true

    /// The list on show, which a conversation opens from: the stack's, or the one beside the reader. `nil` in a
    /// narrow window back at the mailboxes.
    public var list: UIViewController? {
        guard let list = listMade?.screen else { return nil }
        if arrangement == .stack, !stackScreens.contains(where: { $0 === list }) { return nil }
        return list
    }

    /// The list on show as the window reads conversations through it.
    public var front: (any ThreadSequence)? {
        list as? any ThreadSequence
    }

    /// The reader on show.
    public var reader: ThreadViewController? {
        readerMade?.screen
    }

    /// Shows `state` in `arrangement`, with `row` the conversation read's when the window has it, moving the list and
    /// the reader there from the other arrangement. A reader that can't be made leaves the list showing, and the
    /// result says so, for the navigation to say it is gone.
    @discardableResult
    public func show(
        _ state: WindowState, row: ThreadSummary?, _ showing: Showing, in arrangement: WindowNavigation.Arrangement
    ) -> Bool {
        let moved = arrangement != self.arrangement
        self.arrangement = arrangement
        let before = (list: listMade?.screen, reading: readerMade?.entry)
        let list =
            listMade.flatMap { $0.entry == state.list ? $0 : nil }
            ?? Made(entry: state.list, screen: makers.list(state.list))
        listMade = list
        let previous = readerMade?.screen
        readerMade = state.reading.flatMap { reader(for: $0, row: row) }
        let readable = state.reading == nil || readerMade != nil
        readerMade?.screen.steps = arrangement == .stack ? steps : nil
        switch arrangement {
        case .stack:
            if moved { leaveColumns() }
            arrangeStack(state, showing: showing, replacing: previous)
        case .columns:
            if moved { leaveStack() }
            arrangeColumns(state, showing: showing, replacing: previous)
        }
        // Where the reader's chevrons lead may have changed with the rest.
        readerMade?.screen.setNeedsUpdateProperties()
        if moved || list.screen !== before.list || readerMade?.entry != before.reading {
            (list.screen as? any ThreadSequence)?.mark(reading: readerMade?.entry.thread)
        }
        showCategory(of: state, in: list.screen)
        return readable
    }

    /// Counts the rows picked beside the list, while nothing is read.
    public func showPicked(_ count: Int) {
        (detailColumn.topViewController as? NoThreadViewController)?.selectedCount = count
    }

    /// Runs `body` once the stack has settled from the change under way, if one is.
    public func whenSettled(_ body: @escaping () -> Void) {
        guard let transition = stack.transitionCoordinator else { return body() }
        transition.animate(alongsideTransition: nil) { _ in body() }
    }

    // MARK: Columns

    private func arrangeColumns(_ state: WindowState, showing: Showing, replacing previous: ThreadViewController?) {
        let sidebar = sidebar ?? makers.mailboxes(.sidebar)
        if self.sidebar == nil {
            self.sidebar = sidebar
            sidebarColumn.setViewControllers([sidebar], animated: false)
        }
        if sidebar.selected != state.destination { sidebar.selected = state.destination }
        if let list = listMade?.screen, listColumn.viewControllers.first !== list {
            listColumn.setViewControllers([list], animated: false)
        }
        guard let reader = readerMade?.screen else {
            let closed = detailColumn.topViewController is ThreadViewController
            showNothing()
            if closed, showing == .announced, let list = listMade?.screen {
                SystemAccessibility.post(.screenChanged, argument: list.view)
            }
            return
        }
        guard detailColumn.viewControllers.first !== reader else { return }
        if showing == .announced, reader !== previous { reader.announceWhenShown() }
        detailColumn.setViewControllers([reader], animated: false)
        if showing != .resized { split.show(.secondary) }
    }

    /// The pane beside the list with nothing read, kept as it is when it already says so.
    private func showNothing() {
        guard !(detailColumn.topViewController is NoThreadViewController) else { return }
        detailColumn.setViewControllers([NoThreadViewController()], animated: false)
    }

    /// Takes the list and the reader out of the columns, for the stack to show them.
    private func leaveColumns() {
        listColumn.setViewControllers([], animated: false)
        showNothing()
    }

    // MARK: Stack

    private func arrangeStack(_ state: WindowState, showing: Showing, replacing previous: ThreadViewController?) {
        var screens: [UIViewController] = []
        for entry in state.stack {
            switch entry {
            case .mailboxes:
                let mailboxes = stackMailboxes ?? makers.mailboxes(.list)
                stackMailboxes = mailboxes
                if mailboxes.selected != state.destination { mailboxes.selected = state.destination }
                screens.append(mailboxes)
            case .list:
                if let list = listMade?.screen { screens.append(list) }
            case .reader:
                if let reader = readerMade?.screen { screens.append(reader) }
            }
        }
        let moving = showing != .resized
        let replacingReader = moving && previous != nil && readerMade != nil
        if let reader = readerMade?.screen, reader !== previous, showing == .announced || replacingReader {
            // A reader the window put there by itself, or one in another's place, which UIKit doesn't announce.
            reader.announceWhenShown()
        }
        setStack(screens, animated: moving, replacingReader: replacingReader)
    }

    /// Takes the list and the reader off the stack, for the columns to show them, leaving the mailboxes.
    private func leaveStack() {
        let kept = stack.viewControllers.filter { $0 === stackMailboxes }
        stackScreens = kept
        stack.setViewControllers(kept, animated: false)
    }

    /// Sets the stack to `screens` in one go: a push or a pop, or a short cross-fade (none under Reduce Motion) when a
    /// reader takes another's place.
    private func setStack(_ screens: [UIViewController], animated: Bool, replacingReader: Bool) {
        let old = stackScreens
        guard !screens.elementsEqual(old, by: ===) else { return }
        stackScreens = screens
        let onScreen = animated && stack.view.window != nil
        guard replacingReader, screens.last !== old.last else {
            return stack.setViewControllers(screens, animated: onScreen)
        }
        guard onScreen, !SystemAccessibility.reducesMotion else {
            return stack.setViewControllers(screens, animated: false)
        }
        UIView.transition(with: stack.view, duration: 0.25, options: .transitionCrossDissolve) {
            self.stack.setViewControllers(screens, animated: false)
        }
    }

    // MARK: Helpers

    /// The reader for `reading`: the one shown when it was made for it, else a new one from `row` or the list's, or
    /// `nil` when none can be made.
    private func reader(for reading: Reading, row: ThreadSummary?) -> Made<Reading, ThreadViewController>? {
        if let made = readerMade, made.entry == reading { return made }
        let summary =
            row.flatMap { $0.id == reading.thread ? $0 : nil }
            ?? (listMade?.screen as? any ThreadSequence)?.summary(of: reading.thread)
        guard let summary else { return nil }
        return makers.reader(reading, summary).map { Made(entry: reading, screen: $0) }
    }

    /// Has an Inbox `list` show the category `state` names, which an arrival from outside can change under it (R4).
    private func showCategory(of state: WindowState, in list: UIViewController) {
        (list as? MailboxViewController)?.showCategory(state.category)
    }
}

extension MailScreens: UINavigationControllerDelegate {
    /// The stack went back by itself, by its Back button or edge swipe: the navigation follows.
    public func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
        // The stack the screens left for the columns isn't the reader's to go back in.
        guard arrangement == .stack else { return }
        let screens = navigationController.viewControllers
        guard !screens.elementsEqual(stackScreens, by: ===) else { return }
        let hadReader = stackScreens.contains { $0 is ThreadViewController }
        stackScreens = screens
        if screens.count == 1 {
            wentBack?(.mailboxes)
        } else if hadReader, !screens.contains(where: { $0 is ThreadViewController }) {
            wentBack?(.list)
        }
    }
}
