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
    private var swipes: SwipeActionsController!
    private let searchResults: SearchResultsController?
    /// What an empty list shows.
    private let empty: UIContentUnavailableConfiguration
    private var emptyState: EmptyState?

    private enum EmptyState: Equatable {
        /// Spam and Trash start empty while their first page is fetched.
        case loading
        /// With another category that has unread mail to point to.
        case empty(pointingTo: InboxCategory?)
    }
    private var browsingToolbarItems: [UIBarButtonItem] = []
    /// The Inbox's category menu, when the list is split into categories.
    private let categoryButton: UIButton?
    private let categoryItem: UIBarButtonItem?

    /// `searchResults`, when given, adds search to the toolbar. `empty` is what an empty list shows: by default the
    /// mailbox's symbol and "No Mail".
    public init(
        viewModel: MailboxViewModel, searchResults: SearchResultsController? = nil,
        empty: UIContentUnavailableConfiguration? = nil
    ) {
        self.viewModel = viewModel
        self.searchResults = searchResults
        self.empty = empty ?? Self.noMail(in: viewModel.mailbox)
        categoryButton = viewModel.category == nil ? nil : Self.categoryButton()
        categoryItem = categoryButton.map { UIBarButtonItem(customView: $0) }
        super.init(nibName: nil, bundle: nil)
        title = viewModel.title
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.leftItemsSupplementBackButton = true
        navigationItem.leftBarButtonItem = categoryItem
        if viewModel.actions != nil { navigationItem.rightBarButtonItem = selectItem() }
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
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.refreshControl = UIRefreshControl(
            frame: .zero,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.viewModel.refresh() }
            }
        )
        view.addSubview(collectionView)
        configureDataSource()
        configureSwipes()
        browsingToolbarItems = [
            searchItem(),
            .flexibleSpace(),
            UIBarButtonItem(
                title: String(localized: "New Message", bundle: .module, comment: "Composer title"),
                image: UIImage(systemName: "square.and.pencil"),
                primaryAction: UIAction { [weak self] _ in self?.viewModel.compose() }),
        ]
        toolbarItems = browsingToolbarItems

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

    /// Search as a glass button in the toolbar that expands into the field, or a gap when there is no search.
    private func searchItem() -> UIBarButtonItem {
        guard let searchResults else { return .flexibleSpace() }
        let search = UISearchController(searchResultsController: searchResults)
        search.searchResultsUpdater = searchResults
        search.searchBar.placeholder = String(
            localized: "Search Mail", bundle: .module, comment: "Placeholder of the search field")
        navigationItem.searchController = search
        navigationItem.preferredSearchBarPlacement = .integratedButton
        navigationItem.searchBarPlacementAllowsToolbarIntegration = true
        definesPresentationContext = true
        return navigationItem.searchBarPlacementBarButtonItem
    }

    /// Called by UIKit whenever an observed view-model property changes.
    public override func updateProperties() {
        super.updateProperties()
        applySections(viewModel.sections)
        updateEmptyState()
        if let categoryButton, let category = viewModel.category {
            Self.update(categoryButton, selected: category, unreadCounts: viewModel.categoryUnreadCounts) {
                [weak self] in self?.show($0)
            }
        }
        if !viewModel.isRefreshing, collectionView.refreshControl?.isRefreshing == true {
            collectionView.refreshControl?.endRefreshing()
        }
    }

    /// Only on a change: setting the configuration lays the view out again, which would run this again.
    private func updateEmptyState() {
        let state: EmptyState? =
            !viewModel.hasLoaded || !viewModel.sections.isEmpty
            ? nil
            : viewModel.isLoadingOlder ? .loading : .empty(pointingTo: viewModel.categoryWithUnread)
        guard state != emptyState else { return }
        emptyState = state
        contentUnavailableConfiguration =
            switch state {
            case nil: nil
            case .loading: UIContentUnavailableConfiguration.loading()
            case .empty(let other?): pointing(empty, to: other)
            case .empty(nil): empty
            }
    }

    /// `configuration` with a link to another category that has unread mail.
    private func pointing(_ configuration: UIContentUnavailableConfiguration, to category: InboxCategory)
        -> UIContentUnavailableConfiguration
    {
        var configuration = configuration
        var button = UIButton.Configuration.plain()
        button.title = String(
            localized: "Go to \(category.title)", bundle: .module,
            comment: "Link from an empty Inbox category to another with unread mail")
        configuration.button = button
        configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.show(category) }
        return configuration
    }

    /// Switches to `category`'s threads, from the top.
    private func show(_ category: InboxCategory) {
        viewModel.select(category)
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
    }

    private static func noMail(in mailbox: Mailbox) -> UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: mailbox.symbol)
        configuration.text = String(localized: "No Mail", bundle: .module, comment: "An empty mailbox")
        return configuration
    }

    private func configureSwipes() {
        swipes = SwipeActionsController(collectionView: collectionView)
        swipes.actions = { [weak self] indexPath, edge in
            guard let self, !isEditing, let id = dataSource.itemIdentifier(for: indexPath) else { return [] }
            return swipeActions(for: id, leading: edge == .leading)
        }
    }

    private func swipeActions(for id: ThreadSummary.ID, leading: Bool) -> [SwipeAction] {
        guard let thread = threadsByID[id] else { return [] }
        return viewModel.swipeActions(for: thread, leading: leading).map { action in
            SwipeAction(title: action.title, symbol: action.symbol, isDestructive: action.isDestructive) {
                [weak self] in self?.viewModel.perform(action, on: [id])
            }
        }
    }

    private func configureDataSource() {
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, ThreadSummary.ID> {
            [weak self] cell, _, id in
            guard let self, let thread = threadsByID[id] else { return }
            cell.accessories = [.multiselect(displayed: .whenEditing)]
            cell.contentConfiguration = ThreadRowConfiguration(
                thread: thread,
                dateText: viewModel.dateText(for: thread),
                accountColor: viewModel.accountColors[thread.id.accountID]?.uiColor ?? .tintColor
            )
            // The open thread stays selected beside the list on iPad; a light tint keeps its text readable.
            cell.configurationUpdateHandler = { cell, state in
                var background = UIBackgroundConfiguration.listCell().updated(for: state)
                if state.isSelected || state.isHighlighted {
                    background.backgroundColor = .tintColor.withAlphaComponent(0.14)
                }
                cell.backgroundConfiguration = background
            }
            // VoiceOver reaches the swipe actions through the rotor.
            cell.accessibilityCustomActions =
                (swipeActions(for: id, leading: false)
                + swipeActions(for: id, leading: true)).map { action in
                    UIAccessibilityCustomAction(name: action.title) { _ in
                        action.handler()
                        return true
                    }
                }
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
        // Selected threads may have left the list.
        if isEditing { updateSelectionChrome() }
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

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        swipes.close()
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        // A tap while actions are open just closes them.
        !swipes.close()
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isEditing { return updateSelectionChrome() }
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        // Search results sit outside the navigation stack, so they never see the reader close to deselect then.
        if navigationController == nil { collectionView.deselectItem(at: indexPath, animated: true) }
        viewModel.open(id)
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if isEditing { updateSelectionChrome() }
    }
}

// MARK: - Selecting several threads

extension MailboxViewController {
    private func selectItem() -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(localized: "Select", bundle: .module, comment: "Starts selecting several threads"),
            primaryAction: UIAction { [weak self] _ in self?.setEditing(true, animated: true) })
    }

    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        swipes.close(animated: animated)
        collectionView.isEditing = editing
        navigationItem.hidesBackButton = editing
        navigationItem.rightBarButtonItem =
            editing
            ? UIBarButtonItem(
                systemItem: .done,
                primaryAction: UIAction { [weak self] _ in self?.setEditing(false, animated: true) })
            : selectItem()
        if editing {
            updateSelectionChrome()
        } else {
            navigationItem.leftBarButtonItem = categoryItem
            title = viewModel.title
            setToolbarItems(browsingToolbarItems, animated: animated)
        }
    }

    private var selectedIDs: [ThreadSummary.ID] {
        (collectionView.indexPathsForSelectedItems ?? []).compactMap(dataSource.itemIdentifier)
    }

    /// The title, Select All and the toolbar's actions, for what is selected now.
    private func updateSelectionChrome() {
        let ids = selectedIDs
        let snapshot = dataSource.snapshot()
        let allSelected = !ids.isEmpty && ids.count == snapshot.numberOfItems
        title =
            ids.isEmpty
            ? viewModel.title
            : String(localized: "\(ids.count) Selected", bundle: .module, comment: "Title while selecting threads")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: allSelected
                ? String(localized: "Deselect All", bundle: .module, comment: "Clears the selection")
                : String(localized: "Select All", bundle: .module, comment: "Selects every thread in the list"),
            primaryAction: UIAction { [weak self] _ in self?.selectAll(!allSelected) })

        // With nothing selected, show what the list as a whole allows, disabled, so the toolbar doesn't jump.
        let threads = (ids.isEmpty ? snapshot.itemIdentifiers : ids).compactMap { threadsByID[$0] }
        let actions = MailboxViewModel.bulkActions(for: threads)
        let items = actions.map { action in
            let item = UIBarButtonItem(
                title: action.title, image: UIImage(systemName: action.symbol),
                primaryAction: UIAction { [weak self] _ in self?.performOnSelection(action) })
            item.isEnabled = !ids.isEmpty
            return item
        }
        // Labels belong to an account, so the picker opens for one account's threads at a time.
        let labels = UIBarButtonItem.changeLabels { [weak self] in
            guard let self else { return }
            viewModel.changeLabels(of: selectedIDs)
            setEditing(false, animated: true)
        }
        labels.isEnabled = Set(threads.map(\.id.accountID)).count == 1 && !ids.isEmpty
        setToolbarItems(
            Array(items.prefix(1)) + [labels, .flexibleSpace()] + items.dropFirst(), animated: false)
    }

    private func selectAll(_ select: Bool) {
        for item in dataSource.snapshot().itemIdentifiers {
            guard let indexPath = dataSource.indexPath(for: item) else { continue }
            if select {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            } else {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
        updateSelectionChrome()
    }

    private func performOnSelection(_ action: ThreadAction) {
        viewModel.perform(action, on: selectedIDs)
        setEditing(false, animated: true)
    }
}
