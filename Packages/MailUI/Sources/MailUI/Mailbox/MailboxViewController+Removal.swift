import MailCore
import UIKit

// MARK: - Deleting

extension MailboxViewController {
    /// Whether the list takes changes as they come.
    enum ListMotion {
        case free
        /// Rows are breaking into dust over their hidden cells. The list holds still until the dust has blown clear,
        /// so the rows below don't slide in under text that hasn't broken up yet, then catches up in one change.
        case dissolving([ThreadSummary.ID], release: Task<Void, Never>)
        /// These rows are going into a box. The list holds still, so they lift off where they are, and catches up
        /// in one change once they are in.
        case stowing([ThreadSummary.ID])
    }

    static let deletedWindow = Duration.seconds(2)

    /// Performs `action`, then `done`. Delete Forever asks first, and on Cancel does neither.
    func perform(_ action: ThreadAction, on ids: [ThreadSummary.ID], then done: @escaping () -> Void = {}) {
        guard action == .deleteForever else {
            viewModel.perform(action, on: ids)
            return done()
        }
        let everything = viewModel.isTrash && ids.count == dataSource.snapshot().numberOfItems
        let alert = UIAlertController.deleteForever(everything ? .trash(ids.count) : .threads(ids.count)) {
            [weak self] in
            guard let self else { return }
            let now = ContinuousClock.now
            for id in ids { deleted[id] = now }
            viewModel.perform(.deleteForever, on: ids)
            done()
        }
        present(alert, animated: true)
    }

    /// Breaks the rows of threads deleted forever that are leaving the list into dust and holds the list still while
    /// it blows clear. With Reduce Motion on, they fade out with the list's own deletion instead. Returns whether any
    /// row dissolves, in which case the list takes this change once the hold ends.
    func dissolveDeleted(leaving threads: [ThreadSummary.ID: ThreadSummary]) -> Bool {
        let now = ContinuousClock.now
        deleted = deleted.filter { now - $0.value < Self.deletedWindow }
        let leaving = deleted.keys.filter { threads[$0] == nil }
        guard !leaving.isEmpty else { return false }
        for id in leaving { deleted[id] = nil }
        guard view.window != nil, Motion.playsRemovals else { return false }
        let rows = leaving.compactMap { id in
            dataSource.indexPath(for: id).flatMap(collectionView.cellForItem).map { (id, $0) }
        }
        guard !rows.isEmpty else { return false }
        for (_, cell) in rows {
            DissolveView.dissolve(cell, in: collectionView, budget: DissolveView.particleBudget / rows.count)
        }
        let release = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(DissolveField.sweep))) != nil else { return }
            self?.endDissolving()
        }
        listMotion = .dissolving(rows.map(\.0), release: release)
        return true
    }

    /// Lets the list catch up with every change held back while rows dissolved. A thread that came back meanwhile, as
    /// one a fetch restored, shows its row again.
    private func endDissolving() {
        guard case .dissolving(let ids, _) = listMotion else { return }
        listMotion = .free
        applySections(viewModel.sections)
        updateEmptyState()
        for id in ids {
            dataSource.indexPath(for: id).flatMap(collectionView.cellForItem)?.alpha = 1
        }
    }
}

// MARK: - Putting threads away

extension MailboxViewController {
    /// Does `action` on `ids` and flies the rows on screen into `box`, holding the list still meanwhile. Once they
    /// are in, `finish` runs and the list closes the gaps. Off screen, or while other rows are still going in, the
    /// action just happens.
    func stow(
        _ ids: [ThreadSummary.ID], into box: StowBoxView, doing action: ThreadAction,
        then finish: @escaping () -> Void
    ) {
        guard case .free = listMotion, let window = view.window else {
            viewModel.perform(action, on: ids)
            return finish()
        }
        let cells = ids.compactMap { dataSource.indexPath(for: $0).flatMap(collectionView.cellForItem) }
        listMotion = .stowing(ids)
        collectionView.isUserInteractionEnabled = false
        viewModel.perform(action, on: ids)
        StowFlight.run(cells, into: box, over: window) { [weak self] in
            finish()
            self?.endStowing()
        }
    }

    /// Lets the list catch up with every change held back while rows went into their box. A thread that came back
    /// meanwhile, as on a quick Undo, shows its row again.
    private func endStowing() {
        guard case .stowing(let ids) = listMotion else { return }
        listMotion = .free
        collectionView.isUserInteractionEnabled = true
        applySections(viewModel.sections)
        updateEmptyState()
        for id in ids {
            dataSource.indexPath(for: id).flatMap(collectionView.cellForItem)?.contentView.alpha = 1
        }
    }
}
