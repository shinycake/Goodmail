import MailCore
import MailUI
import UIKit

/// Where the reader goes after the reader asks a change of mail in this window, and only then (R6–R9). The window's
/// actions tell it of each change as it is asked, before it applies, and of each Undo, and `ReaderCourse` decides from
/// what shows now: what sync, other devices, alerts and other windows change only changes rows.
///
/// Every reader the window shows comes on screen through `showReader(_:announcing:)`, and every reader it closes goes through
/// `closeReader()`: the narrow stack never holds two (R1), and the list always marks the one read (R11).
extension SceneCoordinator {
    /// Follows what the reader asks of the window's actions. Called once, as the window is made.
    func followReaderChanges() {
        actions.changed = { [weak self] change in self?.readerAsked(change) }
        actions.undone = { [weak self] change in self?.readerUndid(change) }
    }

    /// Opens `id`, read in `mailbox`, as the window was asked to by a tap, a click, an alert or a link: in place of
    /// the conversation on show, if one is. One gone from the device does nothing.
    func openReader(_ id: ThreadSummary.ID, in mailbox: Mailbox) {
        guard let split, let reader = reader(for: id, in: mailbox) else { return }
        course.opened(id, from: frontSequence?.frontRows ?? [])
        // A narrow window replacing a reader, as an alert's does over one open, is no push UIKit announces.
        let replacing = split.isCollapsed && navigation(for: .compact)?.readerPlacement != .push
        showReader(reader, announcing: replacing)
    }

    private func readerAsked(_ change: MailChange) {
        let list = frontSequence
        let facts = ReaderCourse.Facts(
            reader: readerOnShow?.reading, front: list?.courseFront, layout: shown.layout,
            setting: Preferences.afterRemoval)
        switch course.asked(change, facts) {
        case .stays:
            break
        case .closes:
            closeReader()
        case .opens(let next):
            // One gone from the device leaves the list instead.
            guard let reader = reader(for: next, listedIn: list) else { return closeReader() }
            showReader(reader, announcing: true)
        case .leavesWindow:
            leaveMessage()
        }
    }

    /// Undo took back what left a conversation: it opens again unless the window has moved on since (R9).
    /// The reader is built from the row as it was read, so nothing is read from the store here (`WindowCourse`).
    private func readerUndid(_ change: MailChange) {
        let list = frontSequence
        guard split != nil, let left = course.undone(change, rows: list?.frontRows ?? []),
            let reader = reader(for: left.summary, in: left.mailbox)
        else { return }
        showReader(reader, announcing: true)
    }

    /// A reader for `opening`, from the row the list on show holds when it holds one, else from the store.
    private func reader(for opening: ReaderCourse.Opening, listedIn list: (any ThreadSequence)?)
        -> ThreadViewController?
    {
        if let summary = list?.summary(of: opening.thread) { return reader(for: summary, in: opening.mailbox) }
        return reader(for: opening.thread, in: opening.mailbox)
    }

    /// The list a conversation opens from, as the window shows it now: the narrow stack's, or the one beside the reader.
    var frontSequence: (any ThreadSequence)? {
        guard let split else { return nil }
        guard split.isCollapsed else {
            return navigation(for: .supplementary)?.viewControllers.first as? any ThreadSequence
        }
        return navigation(for: .compact)?.viewControllers.lazy.compactMap { $0 as? any ThreadSequence }.last
    }

    /// The reader on show: at the top of the narrow stack, beside the list, or alone in a message window.
    private var readerOnShow: ThreadViewController? {
        switch screen {
        case .message(let content, _):
            return (content as? UINavigationController)?.viewControllers.first as? ThreadViewController
        case .mailbox(let split, _, _):
            let pane = navigation(for: split.isCollapsed ? .compact : .secondary)
            return pane?.topViewController as? ThreadViewController
        case .starting, .welcome, .offer, .leaving:
            return nil
        }
    }

    /// Back to the list, with nothing open and no row marked read. A narrow window pops, which UIKit announces; beside
    /// the list, VoiceOver goes back to the list from the emptied pane.
    private func closeReader() {
        guard let split else { return }
        course.landed(on: nil)
        let list = frontSequence
        list?.mark(reading: nil)
        if split.isCollapsed {
            navigation(for: .compact)?.popViewController(animated: true)
        } else {
            navigation(for: .secondary)?.setViewControllers([NoThreadViewController()], animated: false)
            SystemAccessibility.post(.screenChanged, argument: (list as? UIViewController)?.view)
        }
    }

    /// Shows `reader`, of a conversation of the list on show, in the place of the reader on show, and marks its row.
    /// `announcing` moves VoiceOver to its subject once it is on screen, for a reader the window put there by itself
    /// (after Archive, Undo, or an alert over an open reader); a tap, a click or an arrow key leaves VoiceOver where
    /// it is, and UIKit announces a push.
    private func showReader(_ reader: ThreadViewController, announcing: Bool) {
        guard let split else { return }
        let thread = reader.reading.thread
        if announcing { reader.announceWhenShown() }
        course.landed(on: thread)
        frontSequence?.mark(reading: thread)
        if split.isCollapsed {
            navigation(for: .compact)?.place(reader)
        } else {
            navigation(for: .secondary)?.setViewControllers([reader], animated: false)
            split.show(.secondary)
        }
    }

    /// The reader on top of the narrow stack is gone, by Back or a swipe: the list no longer marks it, and Undo has
    /// nowhere to bring the reader back to. A pop the window made itself (`closeReader`) closed the thread first.
    func readerPopped() {
        guard shown.openThread != nil else { return }
        move { $0.setThread(nil) }
        frontSequence?.mark(reading: nil)
    }

    /// Search began or ended in the list, so the rows the reader would go on in changed (R9).
    func searchToggled() {
        move { _ in }
    }
}
