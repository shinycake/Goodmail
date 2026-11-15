import MailCore
import UIKit

/// A sheet listing where threads can move: the system places, then the account's labels in their colors. A tap
/// moves them and closes the sheet.
public final class MoveViewController: UIViewController {
    nonisolated private enum Section {
        case places, labels, newLabel
    }

    nonisolated private enum Row: Hashable {
        case destination(MoveDestination)
        case newLabel
    }

    private let viewModel: MoveViewModel
    private lazy var labelEditing = viewModel.editor.map { LabelEditFlow(editor: $0, presenter: self) }
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!

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
        // The places and New Label need no heading; the labels do.
        let layout = UICollectionViewCompositionalLayout { [weak self] section, environment in
            var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let isLabels = self?.dataSource.sectionIdentifier(for: section) == .labels
            list.headerMode = isLabels ? .supplementary : .none
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
        let newLabel = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { cell, _, _ in
            var content = cell.defaultContentConfiguration()
            content.text = String(
                localized: "New Label", table: "LabelEditing", bundle: .module,
                comment: "Action: makes a new label, and the title of the alert that names it")
            content.textProperties.color = .tintColor
            content.image = UIImage(systemName: "plus")
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
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            [weak self] view, path, item in
            switch item {
            case .destination(let id):
                guard let choice = self?.choice(id) else { return nil }
                return view.dequeueConfiguredReusableCell(using: row, for: path, item: choice)
            case .newLabel:
                return view.dequeueConfiguredReusableCell(using: newLabel, for: path, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { view, _, path in
            view.dequeueConfiguredReusableSupplementary(using: header, for: path)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.places])
        snapshot.appendItems(viewModel.places.map { .destination($0.id) })
        if !viewModel.labels.isEmpty {
            snapshot.appendSections([.labels])
            snapshot.appendItems(viewModel.labels.map { .destination($0.id) })
        }
        if viewModel.editor != nil {
            snapshot.appendSections([.newLabel])
            snapshot.appendItems([.newLabel])
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func choice(_ id: MoveDestination) -> MoveViewModel.Choice? {
        (viewModel.places + viewModel.labels).first { $0.id == id }
    }
}

extension MoveViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .destination(let id):
            guard let choice = choice(id) else { return }
            viewModel.move(to: choice)
            dismiss(animated: true)
        case .newLabel:
            collectionView.deselectItem(at: indexPath, animated: true)
            labelEditing?.create { [weak self] label in
                self?.viewModel.move(toNew: label)
                self?.dismiss(animated: true)
            }
        case nil:
            break
        }
    }
}
