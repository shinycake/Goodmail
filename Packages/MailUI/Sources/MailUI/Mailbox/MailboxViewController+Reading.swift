public import MailCore
import UIKit

/// The list as the window reads through it. The window says which row is read (`mark(reading:)`) and the list only
/// shows it, picking nothing of its own when rows leave. What is read lives in one place, the view model's
/// selection; the rows show it whenever it or they change (`showReadRow`).
extension MailboxViewController: ThreadSequence {
    /// The list a conversation is opened from: the search results while search shows them, otherwise this one.
    private var frontList: MailboxViewController {
        guard search?.isActive == true, let results = searchResults?.list else { return self }
        return results
    }

    public var frontSearching: Bool { frontList !== self }

    public var frontRows: [ThreadSummary.ID] { frontList.viewModel.rows }

    public var frontMailbox: Mailbox { frontList.viewModel.mailbox }

    public var pointerPick: [ThreadSummary.ID] {
        guard frontList.picksWithPointer, case .several = frontList.viewModel.selection else { return [] }
        return frontList.viewModel.selectedIDs
    }

    public func summary(of thread: ThreadSummary.ID) -> ThreadSummary? {
        frontList.threadsByID[thread] ?? threadsByID[thread]
    }

    /// Marks `thread` in the list on show, and none in the one search covers or uncovers, so neither marks a
    /// conversation the reader has left.
    public func mark(reading thread: ThreadSummary.ID?) {
        let front = frontList
        for list in [self, searchResults?.list].compactMap(\.self) {
            list.markRead(list === front ? thread : nil)
        }
    }

    private func markRead(_ thread: ThreadSummary.ID?) {
        // Select mode keeps its picks while it is on.
        guard !isEditing else { return }
        viewModel.markReading(thread)
        showReadRow()
        revealReadRow()
    }

    /// Shows on the rows the conversation the view model says is read. A pointer's pick shows itself (`showPick`);
    /// touch selects that row alone, once it is listed, and no row while none is read.
    func showReadRow() {
        guard isViewLoaded, !isEditing, !picksWithPointer else { return }
        let read = readRow
        for selected in collectionView.indexPathsForSelectedItems ?? [] where selected != read {
            collectionView.deselectItem(at: selected, animated: true)
        }
        guard let read, collectionView.indexPathsForSelectedItems?.contains(read) != true else { return }
        collectionView.selectItem(at: read, animated: false, scrollPosition: [])
    }

    /// Scrolls the row being read into the middle when it is out of sight, as when the list opens on it.
    func revealReadRow() {
        guard isViewLoaded, let read = readRow, !collectionView.indexPathsForVisibleItems.contains(read) else { return }
        collectionView.scrollToItem(at: read, at: .centeredVertically, animated: false)
    }

    /// Where the conversation being read is listed, if it is.
    private var readRow: IndexPath? {
        guard case .reading(let thread) = viewModel.selection else { return nil }
        return dataSource.indexPath(for: thread)
    }
}
