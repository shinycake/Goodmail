import MailCore
public import UIKit

/// Picking rows in a desktop window, without a Select mode: clicks with ⌘ and ⇧, the arrows, ⌘A, Escape, Return and
/// Delete. The view model holds the pick (`ListSelection`) and the list only shows it; the collection view never picks
/// a row itself here (`shouldSelectItemAt`). On touch the collection view picks, as it always has, and tells the view
/// model what (`reportTouchPick`).
extension MailboxViewController {
    /// Whether this list picks with a pointer and keys, as its window does.
    var picksWithPointer: Bool { viewModel.interaction == .desktop }

    /// Sets the list up to pick with a pointer, in a desktop window.
    func configurePointerPicking() {
        guard picksWithPointer else { return }
        // Several rows show as selected at once, as the view model picks them.
        collectionView.allowsMultipleSelection = true
        rowClicks = RowClicks(
            on: collectionView,
            click: { [weak self] indexPath, click in self?.click(at: indexPath, click) },
            doubleClick: { [weak self] indexPath in self?.openWindow(at: indexPath) })
    }

    private func click(at indexPath: IndexPath, _ click: ListSelection.Click) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        self.click(id, click)
    }

    /// Picks `id` as a click on its row does.
    func click(_ id: ThreadSummary.ID, _ click: ListSelection.Click) {
        // A click while a row's swipe actions are open just closes them, as a tap does.
        guard !swipes.close() else { return }
        // The keys go to the list after a click in it, as after a click in the reader they go there.
        becomeFirstResponder()
        viewModel.click(id, click)
    }

    private func openWindow(at indexPath: IndexPath) {
        guard DesktopPreferences.doubleClickOpensWindow, UIApplication.shared.supportsMultipleScenes,
            let id = dataSource.itemIdentifier(for: indexPath)
        else {
            return
        }
        viewModel.openInNewWindow(id)
    }

    /// Shows the view model's pick on the rows, changing only the rows whose state differs.
    func showPick() {
        guard picksWithPointer else { return }
        let picked = viewModel.selection.ids
        let shown = Set(collectionView.indexPathsForSelectedItems ?? [])
        for indexPath in shown where !(dataSource.itemIdentifier(for: indexPath).map(picked.contains) ?? false) {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        for id in picked {
            guard let indexPath = dataSource.indexPath(for: id), !shown.contains(indexPath) else { continue }
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }

    /// On touch, tells the view model what the collection view picked: rows in Select mode, or the row open beside
    /// the list.
    func reportTouchPick() {
        guard !picksWithPointer else { return }
        let ids = (collectionView.indexPathsForSelectedItems ?? []).compactMap(dataSource.itemIdentifier)
        viewModel.picked(ids, selecting: isEditing)
    }

    /// The menu a right-click opens: for the whole pick on a picked row, for that row alone on any other.
    func pointerMenu(at point: CGPoint, fallback indexPaths: [IndexPath]) -> UIContextMenuConfiguration? {
        guard let indexPath = collectionView.indexPathForItem(at: point) ?? indexPaths.first,
            let row = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        let ids = viewModel.menuTargets(for: row)
        let threads = ids.compactMap { threadsByID[$0] }
        swipes.close()
        if threads.count > 1 {
            return ThreadMenu.configuration(forSeveral: threads, viewModel: viewModel, presenter: self) {
                [weak self] in self?.perform($0, on: ids)
            }
        }
        guard let thread = threadsByID[row] else { return nil }
        return ThreadMenu.configuration(for: thread, viewModel: viewModel, presenter: self) { [weak self] in
            self?.perform($0, on: [row])
        }
    }

    // MARK: Keys

    public override var canBecomeFirstResponder: Bool { picksWithPointer }

    public override var keyCommands: [UIKeyCommand]? {
        // Nothing behind a screen presented over the list, as the paper plane game, takes its keys.
        guard picksWithPointer, presentedViewController == nil else { return super.keyCommands }
        let keys = ListKey.allCases.filter(answers)
        return (super.keyCommands ?? []) + keys.map { $0.command(action: #selector(press(_:))) }
    }

    /// Whether `key` does anything now.
    private func answers(_ key: ListKey) -> Bool {
        viewModel.answers(key, opensWindows: UIApplication.shared.supportsMultipleScenes)
    }

    @objc private func press(_ command: UIKeyCommand) {
        guard let key = ListKey(command), answers(key) else { return }
        switch key {
        case .up, .extendUp:
            viewModel.move(-1, extending: key.extends)
            reveal(downward: false)
        case .down, .extendDown:
            viewModel.move(1, extending: key.extends)
            reveal(downward: true)
        case .drop:
            viewModel.dropSelection()
        case .openWindow:
            if case .reading(let id) = viewModel.selection { viewModel.openInNewWindow(id) }
        case .delete:
            // In Trash, Delete is for good and asks first; elsewhere it does what this Mac's setting says.
            perform(DesktopPreferences.deleteKey.action(inTrash: viewModel.isTrash), on: viewModel.selectedIDs)
        }
    }

    /// Scrolls the end of the pick the arrows moved into view, when it isn't.
    private func reveal(downward: Bool) {
        let picked = viewModel.selectedIDs
        guard let id = downward ? picked.last : picked.first, let indexPath = dataSource.indexPath(for: id),
            let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame
        else { return }
        let visible = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
        guard !visible.contains(frame) else { return }
        collectionView.scrollToItem(at: indexPath, at: downward ? .bottom : .top, animated: false)
    }

    /// ⌘A, from Edit > Select All: every conversation in the list.
    public override func selectAll(_ sender: Any?) {
        guard picksWithPointer else { return }
        viewModel.selectAll()
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard action == #selector(selectAll(_:)) else {
            return super.canPerformAction(action, withSender: sender)
        }
        return picksWithPointer && !viewModel.rows.isEmpty
    }
}
