import MailCore
import UIKit

/// Shows quick actions on the row a desktop window's pointer rests on: the row tints and the buttons take the time's
/// place (`ThreadRowContentView.quickActions`). One hover recognizer on the list follows the pointer, so no row has
/// to track it. The list says what each row offers (`actions`) and when a change in the list may have altered it
/// (`refresh()`).
final class RowHover: NSObject {
    /// Whether buttons show, and on which row.
    private enum State {
        case away
        case over(ThreadSummary.ID, content: ThreadRowContentView, faces: [HoverAction.Face])
    }

    /// The actions for a row, in order; none while the row offers none, as with a swipe open.
    var actions: (ThreadSummary.ID) -> [HoverAction] = { _ in [] }

    private weak var collectionView: UICollectionView?
    private let rowID: (IndexPath) -> ThreadSummary.ID?
    private let recognizer = UIHoverGestureRecognizer()
    private var state = State.away

    init(on collectionView: UICollectionView, rowID: @escaping (IndexPath) -> ThreadSummary.ID?) {
        self.collectionView = collectionView
        self.rowID = rowID
        super.init()
        recognizer.addTarget(self, action: #selector(hovered))
        collectionView.addGestureRecognizer(recognizer)
    }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        refresh()
    }

    /// Shows the buttons of the row now under the pointer, or none when it is over no row or has left the list.
    /// Called when the pointer moves, and when the list scrolls or changes under a pointer that doesn't.
    func refresh() {
        guard let collectionView, recognizer.state == .began || recognizer.state == .changed,
            let indexPath = collectionView.indexPathForItem(at: recognizer.location(in: collectionView)),
            let id = rowID(indexPath), let cell = collectionView.cellForItem(at: indexPath),
            let content = Self.row(in: cell)
        else { return leave() }
        let offered = actions(id)
        guard !offered.isEmpty else { return leave() }
        let faces = offered.map(\.face)
        if case .over(let shownID, let shown, let shownFaces) = state,
            shownID == id, shown === content, shownFaces == faces
        {
            return
        }
        leave()
        content.quickActions = HoverActionsView(actions: offered)
        state = .over(id, content: content, faces: faces)
    }

    /// The row `cell` shows, if it shows one: a content configuration makes its view the cell's content view.
    static func row(in cell: UICollectionViewCell) -> ThreadRowContentView? {
        cell.contentView as? ThreadRowContentView
    }

    /// A cell left the screen; its row view would otherwise carry the buttons to whichever row reuses it.
    func cellDidEndDisplaying(_ cell: UICollectionViewCell) {
        if case .over(_, let content, _) = state, content.isDescendant(of: cell) { leave() }
    }

    private func leave() {
        if case .over(_, let content, _) = state { content.quickActions = nil }
        state = .away
    }
}
