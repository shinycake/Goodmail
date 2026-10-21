import MailCore
import UIKit

/// The mailbox list. Renders `MailboxViewModel` through Observation and holds no logic of its own (ADR-011).
public final class MailboxViewController: UIViewController {
    private let viewModel: MailboxViewModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<TimeSection, ThreadSummary.ID>!
    private var threadsByID: [ThreadSummary.ID: ThreadSummary] = [:]
    private var sectionTitles: [TimeSection: String] = [:]
    private var observation: Task<Void, Never>?

    public init(viewModel: MailboxViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Inbox", bundle: .module, comment: "Mailbox title")
        navigationItem.largeTitleDisplayMode = .always
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    deinit {
        observation?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.headerMode = .supplementary
        list.separatorConfiguration.bottomSeparatorInsets.leading = ThreadRowMetrics.textLeadingInset
        collectionView = UICollectionView(
            frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: list))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.accessibilityIdentifier = "mailbox"
        collectionView.delegate = self
        collectionView.refreshControl = UIRefreshControl(
            frame: .zero,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.viewModel.refresh() }
            }
        )
        view.addSubview(collectionView)
        configureDataSource()

        observation = Task { [viewModel] in await viewModel.observe() }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.navigationBar.largeTitleTextAttributes = [
            .font: Typography.serif(.largeTitle, weight: .bold)
        ]
    }

    /// Called by UIKit whenever an observed view-model property changes.
    public override func updateProperties() {
        super.updateProperties()
        applySections(viewModel.sections)
        if !viewModel.isRefreshing, collectionView.refreshControl?.isRefreshing == true {
            collectionView.refreshControl?.endRefreshing()
        }
    }

    private func configureDataSource() {
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, ThreadSummary.ID> {
            [weak self] cell, _, id in
            guard let self, let thread = threadsByID[id] else { return }
            cell.contentConfiguration = ThreadRowConfiguration(
                thread: thread,
                dateText: viewModel.dateText(for: thread),
                accountColor: viewModel.accountColors[thread.id.accountID]?.uiColor ?? .tintColor
            )
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] cell, _, indexPath in
            guard let self, let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }
            var content = UIListContentConfiguration.header()
            content.text = sectionTitles[section]
            cell.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, id in
            view.dequeueConfiguredReusableCell(using: row, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { view, _, indexPath in
            view.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    private func applySections(_ sections: [MailboxViewModel.Section]) {
        var snapshot = NSDiffableDataSourceSnapshot<TimeSection, ThreadSummary.ID>()
        var changed: [ThreadSummary.ID] = []
        var threads: [ThreadSummary.ID: ThreadSummary] = [:]
        threads.reserveCapacity(threadsByID.count)
        for section in sections {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.threads.map(\.id), toSection: section.id)
            for thread in section.threads {
                if let previous = threadsByID[thread.id], previous != thread { changed.append(thread.id) }
                threads[thread.id] = thread
            }
        }
        snapshot.reconfigureItems(changed)
        let titlesChanged = sectionTitles != Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.title) })
        threadsByID = threads
        sectionTitles = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.title) })
        if titlesChanged { snapshot.reloadSections(snapshot.sectionIdentifiers) }
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }
}

extension MailboxViewController: UICollectionViewDelegate {
    /// How close to the last row the next older page is requested, so it arrives before the user gets there.
    private static let loadOlderLead = 20

    public func collectionView(
        _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        let snapshot = dataSource.snapshot()
        guard let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }
        let before = snapshot.sectionIdentifiers.prefix { $0 != section }
            .reduce(0) { $0 + snapshot.numberOfItems(inSection: $1) }
        guard snapshot.numberOfItems - (before + indexPath.item) <= Self.loadOlderLead else { return }
        Task { [viewModel] in await viewModel.loadOlderIfNeeded() }
    }
}
