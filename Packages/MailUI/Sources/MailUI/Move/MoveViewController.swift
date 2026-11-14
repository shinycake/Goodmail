import MailCore
import UIKit

/// A sheet listing where threads can move: the system places, then the account's labels in their colors. A tap
/// moves them and closes the sheet.
public final class MoveViewController: UIViewController {
    private enum Section: Int {
        case places, labels
    }

    private let viewModel: MoveViewModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, MoveDestination>!

    public init(viewModel: MoveViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = String(
            localized: "move.title", defaultValue: "Move To", table: "Move", bundle: .module,
            comment: "Title of the sheet that picks where threads move")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        // The places need no heading; the labels do.
        let layout = UICollectionViewCompositionalLayout { section, environment in
            var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            list.headerMode = section == Section.labels.rawValue ? .supplementary : .none
            return .list(using: list, layoutEnvironment: environment)
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        view.addSubview(collectionView)

        let row = UICollectionView.CellRegistration<UICollectionViewListCell, MoveViewModel.Choice> { cell, _, choice in
            var content = cell.defaultContentConfiguration()
            content.text = choice.name
            content.image = UIImage(systemName: choice.symbol)
            content.imageProperties.tintColor = UIColor(labelColor: choice.color) ?? .tintColor
            cell.contentConfiguration = content
            cell.accessibilityTraits.insert(.button)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { cell, _, _ in
            var content = cell.defaultContentConfiguration()
            content.text = String(
                localized: "Labels", table: "Move", bundle: .module,
                comment: "Section of user labels in the mailbox list")
            cell.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] view, path, id in
            guard let choice = self?.choice(id) else { return nil }
            return view.dequeueConfiguredReusableCell(using: row, for: path, item: choice)
        }
        dataSource.supplementaryViewProvider = { view, _, path in
            view.dequeueConfiguredReusableSupplementary(using: header, for: path)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, MoveDestination>()
        snapshot.appendSections([.places])
        snapshot.appendItems(viewModel.places.map(\.id))
        if !viewModel.labels.isEmpty {
            snapshot.appendSections([.labels])
            snapshot.appendItems(viewModel.labels.map(\.id))
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func choice(_ id: MoveDestination) -> MoveViewModel.Choice? {
        (viewModel.places + viewModel.labels).first { $0.id == id }
    }
}

extension MoveViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath), let choice = choice(id) else { return }
        viewModel.move(to: choice)
        dismiss(animated: true)
    }
}
