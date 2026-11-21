public import MailCore
public import UIKit

/// A viewer window's screens, kept showing what its navigation says (`WindowState.stack` and `.columns`): the split
/// view's columns when the window is wide, its one stack when it is narrow. Each change is made in one go, and a screen
/// whose entry is unchanged stays the same screen, so the list keeps its scroll, search and Select mode, and the reader
/// its place and anything typed, across every transition that leaves them be. Back on the stack is reported as
/// `.back`, for the navigation to follow.
///
/// Only the arrangement on show follows each change. The other keeps the screens it showed until the window changes
/// width, and only while nothing changed meanwhile: any change drops them, since a list made for one category or filter
/// would show it stale.
///
/// It tells the list on show which conversation is read, and the sidebar which list is shown, so neither keeps its own
/// idea of either (R11).
public final class MailScreens: NSObject {
    /// What makes each screen.
    public struct Makers {
        public var mailboxes: (MailboxesViewController.Style) -> MailboxesViewController
        public var list: (WindowState.List) -> UIViewController
        /// A reader for the conversation, from its row when the window has it, so the store isn't read; `nil` when it
        /// can't be read, as one whose account is gone.
        public var reader: (Reading, ThreadSummary?) -> ThreadViewController?

        public init(
            mailboxes: @escaping (MailboxesViewController.Style) -> MailboxesViewController,
            list: @escaping (WindowState.List) -> UIViewController,
            reader: @escaping (Reading, ThreadSummary?) -> ThreadViewController?
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

    /// One arrangement's screens, as last shown.
    private struct Arranged {
        var mailboxes: MailboxesViewController?
        var list: Made<WindowState.List, UIViewController>?
        var reader: Made<Reading, ThreadViewController>?

        /// The same, keeping only the mailboxes, which show nothing a change makes stale.
        var forgettingContent: Arranged { Arranged(mailboxes: mailboxes) }
    }

    /// Why the screens show what they show.
    public enum Showing: Equatable, Sendable {
        /// The window moved by itself, after an action or Undo: VoiceOver goes to the new reader, or to the list.
        case announced
        /// The reader moved it, by a tap, a click or keys, which VoiceOver follows on its own.
        case quiet
        /// Nothing moved: the window changed width, and the arrangement it shows now catches up, without animating
        /// or bringing a column forward.
        case resized
    }

    public let split: MailSplitViewController
    private let makers: Makers
    /// Back on the stack, by its button or edge swipe.
    public var wentBack: ((WindowNavigation.Back) -> Void)?
    /// The arrangement shown last.
    public private(set) var arrangement: WindowNavigation.Arrangement

    private let sidebarColumn = UINavigationController()
    private let listColumn = UINavigationController()
    private let detailColumn = UINavigationController()
    private let stack = MailStackController()
    private var columns = Arranged()
    private var stacked = Arranged()
    /// The stack's screens as last set, so a change the stack made itself is told from one made here.
    private var stackScreens: [UIViewController] = []

    /// Builds both arrangements for `state`, in `split`, `arrangement` on show. `row` is the conversation read's, when
    /// the window has it. A reader that can't be made leaves the list showing, and `readable` says so.
    public init(
        _ state: WindowState, row: ThreadSummary?, in split: MailSplitViewController,
        arrangement: WindowNavigation.Arrangement, making makers: Makers
    ) {
        self.split = split
        self.makers = makers
        self.arrangement = arrangement
        super.init()
        stack.delegate = self
        split.setViewController(sidebarColumn, for: .primary)
        split.setViewController(listColumn, for: .supplementary)
        split.setViewController(detailColumn, for: .secondary)
        split.setViewController(stack, for: .compact)
        // Both, so either is ready as the split view settles on one in its window.
        let readableBeside = arrangeColumns(state, row: row, showing: .resized)
        readable = arrangeStack(state, row: row, showing: .resized) && readableBeside
    }

    /// Whether the reader the screens were built with could be made.
    public private(set) var readable = true

    /// The list on show, which a conversation opens from: the stack's, or the one beside the reader. `nil` in a
    /// narrow window back at the mailboxes.
    public var list: UIViewController? {
        current.list?.screen
    }

    /// The list on show as the window reads conversations through it.
    public var front: (any ThreadSequence)? {
        list as? any ThreadSequence
    }

    /// The reader on show.
    public var reader: ThreadViewController? {
        current.reader?.screen
    }

    private var current: Arranged {
        switch arrangement {
        case .stack: stacked
        case .columns: columns
        }
    }

    /// Shows `state` in `arrangement`, with `row` the conversation read's when the window has it. A reader that can't
    /// be made leaves the list showing, and the result says so, for the navigation to say it is gone.
    @discardableResult
    public func show(
        _ state: WindowState, row: ThreadSummary?, _ showing: Showing, in arrangement: WindowNavigation.Arrangement
    ) -> Bool {
        self.arrangement = arrangement
        switch arrangement {
        case .stack:
            if showing != .resized { columns = columns.forgettingContent }
            return arrangeStack(state, row: row, showing: showing)
        case .columns:
            if showing != .resized { stacked = stacked.forgettingContent }
            return arrangeColumns(state, row: row, showing: showing)
        }
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

    private func arrangeColumns(_ state: WindowState, row: ThreadSummary?, showing: Showing) -> Bool {
        let before = columns
        let wanted = state.columns
        let sidebar = before.mailboxes ?? makers.mailboxes(.sidebar)
        if before.mailboxes == nil { sidebarColumn.setViewControllers([sidebar], animated: false) }
        if sidebar.selected != state.destination { sidebar.selected = state.destination }
        columns.mailboxes = sidebar

        let list = reused(before.list, for: wanted.list) ?? Made(entry: wanted.list, screen: makers.list(wanted.list))
        if list.screen !== before.list?.screen { listColumn.setViewControllers([list.screen], animated: false) }
        columns.list = list

        var readable = true
        switch wanted.detail {
        case .reader(let reading):
            if let reader = reader(for: reading, row: row, reusing: before.reader) {
                columns.reader = reader
                if reader.screen !== before.reader?.screen {
                    if showing == .announced { reader.screen.announceWhenShown() }
                    detailColumn.setViewControllers([reader.screen], animated: false)
                    if showing != .resized { split.show(.secondary) }
                }
            } else {
                readable = false
                showNothing()
            }
        case .nothing:
            let closed = before.reader != nil
            showNothing()
            if closed, showing == .announced { SystemAccessibility.post(.screenChanged, argument: list.screen.view) }
        }
        mark(list.screen, reading: columns.reader?.entry, unlessSameAs: before)
        return readable
    }

    /// The pane beside the list with nothing read, kept as it is when it already says so.
    private func showNothing() {
        columns.reader = nil
        guard !(detailColumn.topViewController is NoThreadViewController) else { return }
        detailColumn.setViewControllers([NoThreadViewController()], animated: false)
    }

    // MARK: Stack

    private func arrangeStack(_ state: WindowState, row: ThreadSummary?, showing: Showing) -> Bool {
        let before = stacked
        var arranged = Arranged()
        var readable = true
        var screens: [UIViewController] = []
        for entry in state.stack {
            switch entry {
            case .mailboxes:
                let mailboxes = before.mailboxes ?? makers.mailboxes(.list)
                arranged.mailboxes = mailboxes
                screens.append(mailboxes)
            case .list(let list):
                let made = reused(before.list, for: list) ?? Made(entry: list, screen: makers.list(list))
                arranged.list = made
                screens.append(made.screen)
            case .reader(let reading):
                guard let made = reader(for: reading, row: row, reusing: before.reader) else {
                    readable = false
                    continue
                }
                arranged.reader = made
                screens.append(made.screen)
            }
        }
        if let mailboxes = arranged.mailboxes, mailboxes.selected != state.destination {
            mailboxes.selected = state.destination
        }
        stacked = arranged
        let moving = showing != .resized
        let replacingReader = moving && before.reader != nil && arranged.reader != nil
        if let reader = arranged.reader?.screen, reader !== before.reader?.screen,
            showing == .announced || replacingReader
        {
            // A reader the window put there by itself, or one in another's place, which UIKit doesn't announce.
            reader.announceWhenShown()
        }
        setStack(screens, animated: moving, replacingReader: replacingReader)
        if let list = arranged.list { mark(list.screen, reading: arranged.reader?.entry, unlessSameAs: before) }
        return readable
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

    /// `made`, when it was made for `entry`.
    private func reused<Entry: Equatable, Screen: UIViewController>(_ made: Made<Entry, Screen>?, for entry: Entry)
        -> Made<Entry, Screen>?
    {
        made?.entry == entry ? made : nil
    }

    /// The reader for `reading`: `made` when it was made for it, else a new one from `row` or the list's, or `nil`
    /// when none can be made.
    private func reader(
        for reading: Reading, row: ThreadSummary?, reusing made: Made<Reading, ThreadViewController>?
    ) -> Made<Reading, ThreadViewController>? {
        if let made = reused(made, for: reading) { return made }
        let row = row.flatMap { $0.id == reading.thread ? $0 : nil } ?? front?.summary(of: reading.thread)
        return makers.reader(reading, row).map { Made(entry: reading, screen: $0) }
    }

    /// Tells `list` which conversation is read, when the list or what is read changed since `before`.
    private func mark(_ list: UIViewController, reading: Reading?, unlessSameAs before: Arranged) {
        guard list !== before.list?.screen || reading != before.reader?.entry else { return }
        (list as? any ThreadSequence)?.mark(reading: reading?.thread)
    }
}

extension MailScreens: UINavigationControllerDelegate {
    /// The stack went back by itself, by its Back button or edge swipe: the navigation follows.
    public func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
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
