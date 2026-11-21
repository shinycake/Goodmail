import UIKit

/// What search offers besides results: saving the search as a smart mailbox, filters for what is typed, and while
/// nothing is, the recent searches.
final class SearchSuggestionsViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable {
        case save
        case filters
        case recent
    }

    nonisolated private enum Item: Hashable {
        case save
        case filter(SearchFilter)
        case search(String)
        case clear
    }

    var onFilter: ((SearchFilter) -> Void)?
    var onSelect: ((String) -> Void)?
    var onClear: (() -> Void)?
    var onSave: (() -> Void)?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

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
            content.imageProperties.tintColor = .secondaryLabel
            switch item {
            case .save:
                content.text = String(
                    localized: "Save as Smart Mailbox", table: "Search", bundle: .module,
                    comment: "Keeps the search in the sidebar as a smart mailbox")
                content.image = UIImage(systemName: "plus.rectangle.on.folder")
                content.textProperties.color = .tintColor
                content.imageProperties.tintColor = .tintColor
            case .filter(let filter):
                content.text = filter.label
                content.secondaryText = filter.detail
                content.secondaryTextProperties.color = .secondaryLabel
                content.image = UIImage(systemName: filter.symbol)
            case .search(let text):
                content.text = text
                content.image = UIImage(systemName: "clock.arrow.circlepath")
            case .clear:
                content.text = String(
                    localized: "Clear Recent Searches", table: "Search", bundle: .module,
                    comment: "Forgets the recent searches")
                content.textProperties.color = .tintColor
            }
            cell.contentConfiguration = content
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            var content = UIListContentConfiguration.header()
            content.text =
                switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
                case .recent:
                    String(
                        localized: "Recent", table: "Search", bundle: .module,
                        comment: "Header above the recent searches")
                case .save: nil
                default:
                    String(
                        localized: "Suggestions", table: "Search", bundle: .module,
                        comment: "Header above the search filters offered for what is typed")
                }
            header.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, item in
            view.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { view, _, indexPath in
            view.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    /// `canSave` offers to keep the search as a smart mailbox, above the rest.
    func show(filters: [SearchFilter], recents: [String], canSave: Bool) {
        loadViewIfNeeded()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if canSave {
            snapshot.appendSections([.save])
            snapshot.appendItems([.save])
        }
        if !filters.isEmpty {
            snapshot.appendSections([.filters])
            snapshot.appendItems(filters.map(Item.filter))
        }
        if !recents.isEmpty {
            snapshot.appendSections([.recent])
            snapshot.appendItems(recents.map(Item.search) + [.clear])
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// The height of everything shown, for showing the suggestions above the results.
    var contentHeight: CGFloat {
        collectionView.layoutIfNeeded()
        return collectionView.contentSize.height
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .save: onSave?()
        case .filter(let filter): onFilter?(filter)
        case .search(let text): onSelect?(text)
        case .clear: onClear?()
        case nil: break
        }
    }
}
