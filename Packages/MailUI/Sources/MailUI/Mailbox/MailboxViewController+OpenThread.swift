import UIKit

extension MailboxViewController {
    /// Marks the row of the thread open beside the list, once it is in the list, so a list rebuilt as the window
    /// widens shows which thread the reader is in, as a tap on the row would have.
    func markOpenThread() {
        guard let thread = threadToMark, !isEditing, let indexPath = dataSource.indexPath(for: thread) else { return }
        threadToMark = nil
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredVertically)
    }
}
