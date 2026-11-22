import MailCore
import UIKit

/// A desktop window's list shows quick actions under the pointer (`RowHover`): the ones picked in the hover settings
/// (`HoverActions`). A touch window, an iPad with a trackpad included, keeps its swipes alone.
extension MailboxViewController {
    func configureHover() {
        guard picksWithPointer else { return }
        let hover = RowHover(on: collectionView, rowID: { [weak self] in self?.dataSource.itemIdentifier(for: $0) })
        hover.actions = { [weak self] id in self?.quickActions(for: id) ?? [] }
        self.hover = hover
    }

    /// The actions for `id`'s row. Each goes through the same path as its swipe button, to that row alone,
    /// whatever else is picked, so the undo toast and the row's motion are the swipe's.
    private func quickActions(for id: ThreadSummary.ID) -> [HoverAction] {
        guard !isEditing, !swipes.isOpen, let thread = threadsByID[id] else { return [] }
        return viewModel.hoverActions(for: thread).map { button in
            let action = swipeAction(button, for: id)
            return HoverAction(
                face: HoverAction.Face(title: action.title, symbol: action.symbol, choice: button.choice),
                run: { action.handler(nil) })
        }
    }
}
