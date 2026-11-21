import MailCore
import MailUI
import UIKit

/// Where the reader goes after the reader asks a change of mail in this window, and only then (R6–R9). The window's
/// actions tell it of each change as it is asked, before it applies, and of each Undo, and `ReaderCourse` decides from
/// what shows now: what sync, other devices, alerts and other windows change only changes rows.
extension SceneCoordinator {
    /// Follows what the reader asks of the window's actions. Called once, as the window is made.
    func followReaderChanges() {
        actions.changed = { [weak self] change in self?.readerAsked(change) }
        actions.undone = { [weak self] change in self?.readerUndid(change) }
    }

    private func readerAsked(_ change: MailChange) {
        let onShow = readerOnShow?.reading
        let list = frontSequence
        let facts = ReaderCourse.Facts(
            reader: onShow, rows: list?.frontRows ?? [], pointerPick: list?.pointerPick ?? [], state: shown,
            setting: Preferences.afterRemoval)
        switch course.asked(change, facts) {
        case .stays:
            break
        case .closes:
            closeReader()
        case .opens(let next):
            // One gone from the device leaves the list instead.
            guard let mailbox = onShow?.mailbox ?? shown.readingMailbox, let reader = reader(for: next, in: mailbox)
            else { return closeReader() }
            place(reader)
        case .leavesWindow:
            leaveMessage()
        }
    }

    /// Undo took back what left a conversation: it opens again if the window still shows where that left it (R9).
    private func readerUndid(_ change: MailChange) {
        guard let left = course.undone(change, in: shown), let reader = reader(for: left.thread, in: left.mailbox)
        else { return }
        place(reader)
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

    /// Back to the list, with nothing open and no row marked read.
    private func closeReader() {
        guard let split else { return }
        shown.setThread(nil)
        frontSequence?.mark(reading: nil)
        if split.isCollapsed {
            navigation(for: .compact)?.popViewController(animated: true)
        } else {
            navigation(for: .secondary)?.setViewControllers([NoThreadViewController()], animated: false)
        }
    }

    /// Shows `reader`, of a conversation of the list on show, in the place of the reader on show, and marks its row. A
    /// narrow window fades one into the other.
    private func place(_ reader: ThreadViewController) {
        guard let split else { return }
        let thread = reader.reading.thread
        let list = frontSequence
        course.opened(thread, from: list?.frontRows ?? [])
        shown.setThread(thread)
        list?.mark(reading: thread)
        if split.isCollapsed {
            navigation(for: .compact)?.showReader(reader)
        } else {
            navigation(for: .secondary)?.setViewControllers([reader], animated: false)
        }
    }
}
