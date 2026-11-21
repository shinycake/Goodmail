import MailCore
import MailUI
import UIKit

/// Where the reader goes after the reader asks a change of mail in this window, and only then (R6–R8). The window's
/// actions tell it of each change as it is asked, before it applies, and `ReaderCourse` decides from what shows now:
/// what sync, other devices, alerts and other windows change only changes rows.
extension SceneCoordinator {
    func readerAsked(_ change: MailChange) {
        let reader = readerOnShow?.reading
        let list = frontSequence
        let facts = ReaderCourse.Facts(
            reader: reader, rows: list?.frontRows ?? [], pointerPick: list?.pointerPick ?? [], layout: shown.layout,
            setting: afterRemoval)
        switch course.asked(change, facts) {
        case .stays:
            break
        case .closes:
            closeReader()
        case .opens(let next):
            guard let mailbox = reader?.mailbox ?? shown.readingMailbox else { return closeReader() }
            read(next, in: mailbox)
        case .leavesWindow:
            leaveMessage()
        }
    }

    /// What the window shows after the conversation read is put away. Until it is a setting, a Mac window goes on to
    /// the next, as Mail on the Mac does, and touch goes back to the list, as it always has.
    private var afterRemoval: AfterRemoval {
        switch window.interactionStyle {
        case .desktop: .next
        case .touch: .list
        }
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

    /// Reads `next`, of the same list, in the place of the reader on show, and marks its row. One gone from the device
    /// leaves the list.
    private func read(_ next: ThreadSummary.ID, in mailbox: Mailbox) {
        guard let split, let reader = reader(for: next, in: mailbox) else { return closeReader() }
        let list = frontSequence
        course.opened(next, from: list?.frontRows ?? [])
        shown.setThread(next)
        list?.mark(reading: next)
        if split.isCollapsed, let stack = navigation(for: .compact) {
            let under = stack.viewControllers.filter { !($0 is ThreadViewController) }
            stack.setViewControllers(under + [reader], animated: false)
        } else {
            navigation(for: .secondary)?.setViewControllers([reader], animated: false)
        }
    }
}
