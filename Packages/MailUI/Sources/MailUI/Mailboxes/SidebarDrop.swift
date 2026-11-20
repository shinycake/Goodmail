import MailCore
import UIKit

/// Takes conversations dragged from the list onto the mailbox rows: Mail's drag to move. A row that can't take them
/// refuses, which the pointer shows, and the row under a valid drop highlights by itself. Holding the option key adds
/// a label instead of moving, where the account can keep several.
final class SidebarDrop: NSObject, UICollectionViewDropDelegate {
    private let viewModel: MailboxesViewModel
    private let destination: (IndexPath) -> MailboxesViewModel.Destination?

    init(viewModel: MailboxesViewModel, destination: @escaping (IndexPath) -> MailboxesViewModel.Destination?) {
        self.viewModel = viewModel
        self.destination = destination
    }

    /// The conversations the session carries, or `nil` when it carries anything else.
    private func dragged(in session: any UIDropSession) -> [DraggedThread]? {
        let items = session.items.compactMap { $0.localObject as? DraggedThread }
        guard !items.isEmpty, items.count == session.items.count else { return nil }
        // A conversation of several messages is several items, and moves once.
        var seen: Set<ThreadSummary.ID> = []
        return items.filter { seen.insert($0.id).inserted }
    }

    /// Holding option takes the move away from the drag, which leaves a copy.
    private func drop(for session: any UIDropSession, at indexPath: IndexPath?) -> (MailDrop, [DraggedThread])? {
        guard let dragged = dragged(in: session), let indexPath, let target = destination(indexPath) else { return nil }
        return (viewModel.drop(of: dragged, onto: target, adding: !session.allowsMoveOperation), dragged)
    }

    func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
        dragged(in: session) != nil
    }

    func collectionView(
        _ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        guard let (drop, _) = drop(for: session, at: destinationIndexPath), drop != .refused else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(
            operation: drop.isCopy ? .copy : .move, intent: .insertIntoDestinationIndexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator
    ) {
        guard let indexPath = coordinator.destinationIndexPath, let target = destination(indexPath),
            let (drop, dragged) = drop(for: coordinator.session, at: indexPath), drop != .refused
        else { return }
        viewModel.perform(drop, of: dragged, onto: target)
    }
}
