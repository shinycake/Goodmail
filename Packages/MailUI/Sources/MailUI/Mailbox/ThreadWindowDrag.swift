import MailCore
import UIKit

/// Lets a thread's row be dragged out of the list to open it in a window of its own, where the device has windows,
/// as in Apple Mail on iPad. The drag carries the new window's state as its activity, which the new window restores.
final class ThreadWindowDrag: NSObject, UICollectionViewDragDelegate {
    /// The thread at a row, or `nil` where a row can't be dragged now, as while selecting several.
    private let thread: (IndexPath) -> ThreadSummary.ID?
    /// The window a dragged thread opens in.
    private let window: (ThreadSummary.ID) -> WindowState
    /// Called as a drag begins, so the list can close what it shows over its rows.
    private let willBegin: () -> Void

    init(
        thread: @escaping (IndexPath) -> ThreadSummary.ID?, window: @escaping (ThreadSummary.ID) -> WindowState,
        willBegin: @escaping () -> Void
    ) {
        self.thread = thread
        self.window = window
        self.willBegin = willBegin
    }

    func collectionView(
        _ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard let id = thread(indexPath), let activity = window(id).activity else { return [] }
        willBegin()
        let provider = NSItemProvider()
        provider.registerObject(activity, visibility: .all)
        let item = UIDragItem(itemProvider: provider)
        item.localObject = id
        return [item]
    }
}
