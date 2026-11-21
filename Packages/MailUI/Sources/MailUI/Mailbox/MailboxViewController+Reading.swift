public import MailCore
import UIKit

/// The list as the window reads through it. The window says which row is read (`mark(reading:)`) and the list only
/// shows it, picking nothing of its own when rows leave.
extension MailboxViewController: ThreadSequence {
    /// The list a conversation is opened from: the search results while search shows them, otherwise this one.
    private var front: MailboxViewController {
        guard search?.isActive == true, let results = searchResults?.list else { return self }
        return results
    }

    public var frontRows: [ThreadSummary.ID] { front.viewModel.rows }

    public var pointerPick: [ThreadSummary.ID] {
        guard front.picksWithPointer, case .several = front.viewModel.selection else { return [] }
        return front.viewModel.selectedIDs
    }

    public func mark(reading thread: ThreadSummary.ID?) {
        let list = front
        list.threadToMark = thread
        if thread == nil { list.unmarkRead() } else { list.markOpenThread() }
    }

    /// Marks the row of the thread open beside the list once it is in the list, as a tap on the row would have, so a
    /// list rebuilt as the window widens shows which thread the reader is in.
    func markOpenThread() {
        guard let thread = threadToMark, isViewLoaded, !isEditing, let indexPath = dataSource.indexPath(for: thread)
        else { return }
        threadToMark = nil
        if !picksWithPointer {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredVertically)
        }
        viewModel.markReading(thread)
    }

    /// The reader closed: no row is read. Select mode and a pointer's several keep their pick.
    private func unmarkRead() {
        guard isViewLoaded, !isEditing, case .reading = viewModel.selection else { return }
        guard !picksWithPointer else { return viewModel.pick(.none, revealing: false) }
        for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
            collectionView.deselectItem(at: indexPath, animated: true)
        }
        reportTouchPick()
    }
}
