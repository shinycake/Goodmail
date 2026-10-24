import MailCore
import UIKit

/// The mailboxes, then the user's labels. The window's root; the Inbox opens on top of it at launch.
public final class MailboxesViewController: UIViewController {
    nonisolated private enum Section: Hashable {
        case standard, labels
    }

    private let viewModel: MailboxesViewModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, MailboxesViewModel.Item>!
    private var observation: Task<Void, Never>?

    public init(viewModel: MailboxesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Mailboxes", bundle: .module, comment: "Title of the list of mailboxes")
        navigationItem.largeTitleDisplayMode = .always
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    deinit {
        observation?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        list.headerMode = .supplementary
        collectionView = UICollectionView(
            frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: list))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.accessibilityIdentifier = "mailboxes"
        collectionView.delegate = self
        view.addSubview(collectionView)
        configureDataSource()
        toolbarItems = [
            .flexibleSpace(),
            UIBarButtonItem(
                title: String(localized: "New Message", bundle: .module, comment: "Composer title"),
                image: UIImage(systemName: "square.and.pencil"),
                primaryAction: UIAction { [weak self] _ in self?.viewModel.compose() }),
        ]
        observation = Task { [viewModel] in await viewModel.observe() }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
            collectionView.deselectItem(at: indexPath, animated: animated)
        }
        navigationController?.setToolbarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.navigationBar.largeTitleTextAttributes = [
            .font: Typography.serif(.largeTitle, weight: .bold)
        ]
    }

    /// Called by UIKit whenever an observed view-model property changes.
    public override func updateProperties() {
        super.updateProperties()
        var snapshot = NSDiffableDataSourceSnapshot<Section, MailboxesViewModel.Item>()
        snapshot.appendSections([.standard])
        snapshot.appendItems(viewModel.standardItems, toSection: .standard)
        let labels = viewModel.labelItems
        if !labels.isEmpty {
            snapshot.appendSections([.labels])
            snapshot.appendItems(labels, toSection: .labels)
        }
        dataSource.apply(snapshot, animatingDifferences: collectionView.window != nil)
    }

    private func configureDataSource() {
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, MailboxesViewModel.Item> {
            cell, _, item in
            var content = UIListContentConfiguration.cell()
            content.text = item.title
            content.image = UIImage(systemName: item.mailbox.symbol)
            content.imageProperties.tintColor = UIColor(labelColor: item.color) ?? .tintColor
            cell.contentConfiguration = content
            var accessories: [UICellAccessory] = [.disclosureIndicator()]
            if item.unreadCount > 0 {
                accessories.insert(.label(text: item.unreadCount.formatted()), at: 0)
            }
            cell.accessories = accessories
            cell.accessibilityIdentifier = "mailbox.\(item.mailbox.labelID ?? "all")"
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            var content = UIListContentConfiguration.header()
            if self?.dataSource.sectionIdentifier(for: indexPath.section) == .labels {
                content.text = String(localized: "Labels", bundle: .module, comment: "Header above the user's labels")
            }
            header.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: row, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }
}

extension MailboxesViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.open(item.mailbox)
    }
}
