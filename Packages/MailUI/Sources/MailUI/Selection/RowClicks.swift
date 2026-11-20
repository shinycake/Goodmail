import MailCore
import UIKit

/// Clicks on a list's rows in a desktop window, read with the keys held, so the list picks rows the way Mail does
/// rather than the way a finger does. A double click comes as a click, then a double click.
final class RowClicks: NSObject, UIGestureRecognizerDelegate {
    private let single = UITapGestureRecognizer()
    private let double = UITapGestureRecognizer()
    private let click: (IndexPath, ListSelection.Click) -> Void
    private let doubleClick: (IndexPath) -> Void

    init(
        on collectionView: UICollectionView, click: @escaping (IndexPath, ListSelection.Click) -> Void,
        doubleClick: @escaping (IndexPath) -> Void
    ) {
        self.click = click
        self.doubleClick = doubleClick
        super.init()
        double.numberOfTapsRequired = 2
        for recognizer in [single, double] {
            recognizer.addTarget(self, action: #selector(clicked(_:)))
            recognizer.delegate = self
            // The row's own highlight still comes and goes under the pointer.
            recognizer.cancelsTouchesInView = false
            collectionView.addGestureRecognizer(recognizer)
        }
    }

    @objc private func clicked(_ recognizer: UITapGestureRecognizer) {
        guard let collectionView = recognizer.view as? UICollectionView,
            let indexPath = collectionView.indexPathForItem(at: recognizer.location(in: collectionView))
        else { return }
        if recognizer === double {
            doubleClick(indexPath)
        } else {
            click(indexPath, Self.click(with: recognizer.modifierFlags))
        }
    }

    /// The single click waits for nothing, so a row picks at once, and the double click comes on top of it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        [single, double].contains(otherGestureRecognizer)
    }

    /// What a click with `modifiers` held does: ⇧ extends, as with ⌘ too, ⌘ adds or takes away, and anything else
    /// reads the row.
    nonisolated static func click(with modifiers: UIKeyModifierFlags) -> ListSelection.Click {
        if modifiers.contains(.shift) { return .extend }
        if modifiers.contains(.command) { return .toggle }
        return .plain
    }
}
