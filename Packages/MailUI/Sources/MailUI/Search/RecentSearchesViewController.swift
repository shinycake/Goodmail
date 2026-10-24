import UIKit

/// The recent searches, shown while the search field is empty. Choosing one searches for it again.
final class RecentSearchesViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Item: Hashable {
        case search(String)
        case clear
    }

    var onSelect: ((String) -> Void)?
    var onClear: (() -> Void)?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!

    override func viewDidLoad() {
        super.viewDidLoad()
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.headerMode = .supplementary
        collectionView = UICollectionView(
            frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: list))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delegate = self
        view.addSubview(collectionView)

        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = UIListContentConfiguration.cell()
            switch item {
            case .search(let text):
                content.text = text
                content.image = UIImage(systemName: "clock.arrow.circlepath")
                content.imageProperties.tintColor = .secondaryLabel
            case .clear:
                content.text = String(
                    localized: "Clear Recent Searches", bundle: .module, comment: "Forgets the recent searches")
                content.textProperties.color = .tintColor
            }
            cell.contentConfiguration = content
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in
            var content = UIListContentConfiguration.header()
            content.text = String(localized: "Recent", bundle: .module, comment: "Header above the recent searches")
            header.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, item in
            view.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { view, _, indexPath in
            view.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    func show(_ searches: [String]) {
        loadViewIfNeeded()
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        if !searches.isEmpty {
            snapshot.appendSections([0])
            snapshot.appendItems(searches.map(Item.search) + [.clear])
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .search(let text): onSelect?(text)
        case .clear: onClear?()
        case nil: break
        }
    }
}
