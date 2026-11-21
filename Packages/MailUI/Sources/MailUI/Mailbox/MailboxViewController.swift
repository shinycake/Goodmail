public import MailCore
public import UIKit

/// The mailbox list. Renders `MailboxViewModel` through Observation and holds no logic of its own (ADR-011).
public final class MailboxViewController: UIViewController {
    let viewModel: MailboxViewModel
    private(set) var collectionView: UICollectionView!
    private(set) var dataSource: UICollectionViewDiffableDataSource<MailboxSection, ThreadSummary.ID>!
    private(set) var threadsByID: [ThreadSummary.ID: ThreadSummary] = [:]
    private var sectionTitles = SectionTitles()
    private var observation: Task<Void, Never>?
    private(set) var swipes: SwipeActionsController!
    /// Quick actions under the pointer, in a desktop window.
    var hover: RowHover?
    /// Picks rows on clicks, in a desktop window (`configurePointerPicking`).
    var rowClicks: RowClicks?
    /// Drags rows onto mailboxes and out of the window. The list's drag delegate, which it doesn't keep.
    private var drag: ConversationDrag?
    let searchResults: SearchResultsController?
    /// The thread open beside a list built after it opened, as when the window widens back into columns, which the
    /// list marks as selected once its row arrives (`markOpenThread`). `nil` once marked.
    public var threadToMark: ThreadSummary.ID?
    /// A search asked for before the list was in a window, as from a Home Screen quick action at launch, which begins
    /// once the list appears (`beginSearch`). `nil` once begun.
    var searchToBegin: SearchQuery?
    /// Search, while browsing: a button in the navigation bar just inside Select, which opens the field there.
    /// Selecting takes it away, so the bar holds Select All, the title and Done.
    private(set) var search: UISearchController?
    let display: RowDisplay
    /// What an empty list shows.
    private let empty: UIContentUnavailableConfiguration
    private var emptyState: EmptyState?
    /// The scene an empty Inbox shows instead, behind the list; `nil` in every other mailbox.
    let inboxZero: InboxZeroModel?
    /// Where the scene is lent, so it can be taken back after the list has left the window.
    var inboxZeroLoan = InboxZeroLoan()
    /// When the reader last took threads out of this list, which tells an Inbox they cleared from one found empty.
    private(set) var lastRemoval: ContinuousClock.Instant?
    /// Threads just deleted forever from this list, with when, so their rows dissolve as they leave. A thread the
    /// store hasn't taken out by then left some other way, or not at all, and goes quietly.
    private var deleted: [ThreadSummary.ID: ContinuousClock.Instant] = [:]
    private static let deletedWindow = Duration.seconds(2)
    private var listMotion = ListMotion.free

    /// Whether the list takes changes as they come.
    private enum ListMotion {
        case free
        /// Rows are breaking into dust over their hidden cells. The list holds still until the dust has blown clear,
        /// so the rows below don't slide in under text that hasn't broken up yet, then catches up in one change.
        case dissolving([ThreadSummary.ID], release: Task<Void, Never>)
        /// These rows are going into a box. The list holds still, so they lift off where they are, and catches up
        /// in one change once they are in.
        case stowing([ThreadSummary.ID])
    }

    enum EmptyState: Equatable {
        /// Spam and Trash start empty while their first page is fetched.
        case loading
        /// With another category that has unread mail to point to.
        case empty(pointingTo: InboxCategory?)
        /// The Inbox is clear, with another category that has unread mail to point to.
        case inboxZero(pointing: InboxZeroPointer?)
        /// The filter leaves nothing of the threads the mailbox has.
        case filtered(ListFilter)
    }
    private var browsingToolbarItems: [UIBarButtonItem] = []
    /// The buttons at the ends of the browsing toolbar: the drafts pill, when the window has one, and Compose.
    private var browsingEnds: [UIBarButtonItem] = []
    /// Tells the drafts pill how many messages are minimized; `nil` for a list with no pill, as search's results.
    private let draftsDock: DraftsDock?
    /// The leading end of the browsing toolbar, while messages are minimized.
    private(set) var draftsPill: DraftsPillItem?
    private lazy var problemsItem = AccountProblemsItem { [weak self] notices in self?.explain(notices) }
    private lazy var select = SelectItem { [weak self] in self?.setEditing(true, animated: true) }
    /// The Inbox's category menu, when the list is split into categories.
    private let categoryButton: UIButton?
    private let categoryItem: UIBarButtonItem?
    /// The filter button in the navigation bar, while the list can be filtered.
    lazy var filterButton = FilterButton { [weak self] in self?.setFilter($0) }

    /// `searchResults`, when given, adds search to the navigation bar. `empty` is what an empty list shows: by
    /// default the mailbox's symbol and "No Mail". `display` is how its rows look. `draftsDock`, when given, puts the
    /// window's drafts pill at the toolbar's leading end.
    public init(
        viewModel: MailboxViewModel, searchResults: SearchResultsController? = nil,
        empty: UIContentUnavailableConfiguration? = nil, display: RowDisplay = Preferences.rowDisplay,
        draftsDock: DraftsDock? = nil
    ) {
        self.viewModel = viewModel
        self.draftsDock = draftsDock
        self.display = display
        self.searchResults = searchResults
        self.empty = empty ?? Self.noMail(in: viewModel.mailbox)
        // Only the Inbox celebrates being empty, and only with its own empty state.
        inboxZero = empty == nil && viewModel.mailbox.labelID == SystemLabel.inbox ? InboxZeroModel() : nil
        categoryButton = viewModel.category == nil ? nil : Self.categoryButton()
        categoryItem = categoryButton.map { UIBarButtonItem(customView: $0) }
        super.init(nibName: nil, bundle: nil)
        title = viewModel.title
        navigationItem.largeTitleDisplayMode = .always
        // The sidebar button stands in for the back button (`browsingLeadingItems`); a root list has neither.
        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    deinit {
        observation?.cancel()
        if case .dissolving(_, let release) = listMotion { release.cancel() }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.headerMode = .supplementary
        list.separatorConfiguration.bottomSeparatorInsets.leading = ThreadRowMetrics.textLeadingInset(for: display)
        collectionView = UICollectionView(
            frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: list))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.accessibilityIdentifier = "mailbox"
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.refreshControl = UIRefreshControl(
            frame: .zero,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.viewModel.refresh() }
            }
        )
        view.addSubview(collectionView)
        if let inboxZero { installInboxZero(inboxZero) }
        configureDataSource()
        configureSwipes()
        configureDrag()
        configurePointerPicking()
        configureHover()
        installSearch()
        navigationItem.rightBarButtonItems = browsingTrailingItems
        let compose = UIBarButtonItem(
            title: String(localized: "New Message", table: "Mailbox", bundle: .module, comment: "Composer title"),
            image: UIImage(systemName: "square.and.pencil"),
            primaryAction: UIAction { [weak self] _ in self?.viewModel.compose() })
        // New Message is the last to go into More when the toolbar runs short, as in a bar down iPhone Duo's side.
        compose.visibilityPriority = .high
        draftsPill = draftsDock?.makePill(for: self)
        browsingToolbarItems = [
            draftsPill?.item ?? .flexibleSpace(), .flexibleSpace(), problemsItem.item, .flexibleSpace(), compose,
        ]
        browsingEnds = [draftsPill?.item, compose].compactMap(\.self)
        toolbarItems = browsingToolbarItems

        observation = Task { [viewModel] in await viewModel.observe() }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A sidebar shown over the list changes only its safe area, which neither scrolls it nor changes its insets.
        placeInboxZero()
    }

    /// Open swipe buttons are laid out for the row's old width, which also sets how far a full swipe goes; a new
    /// width closes them rather than leaving them half shown or one short drag from firing.
    public override func viewWillTransition(
        to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        if size.width != view.bounds.width { swipes.close(animated: false) }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Touch leaves the open thread's row as the reader comes back to the list; a desktop window keeps its pick.
        if !picksWithPointer {
            for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
                collectionView.deselectItem(at: indexPath, animated: animated)
            }
            reportTouchPick()
        }
        navigationController?.setToolbarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        if !isEditing { navigationItem.leftBarButtonItems = browsingLeadingItems }
        wear(viewModel.theme)
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        lendInboxZero()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let searchToBegin { beginSearch(searchToBegin) }
        if picksWithPointer { becomeFirstResponder() }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lendInboxZero()
    }

    /// Search as a glass button in the navigation bar that expands into the field there, when there is search.
    private func installSearch() {
        guard let searchResults else { return }
        let search = UISearchController(searchResultsController: searchResults)
        search.searchResultsUpdater = searchResults
        search.delegate = self
        search.searchBar.placeholder = String(
            localized: "Search Mail", table: "Mailbox", bundle: .module, comment: "Placeholder of the search field")
        self.search = search
        navigationItem.searchController = search
        navigationItem.preferredSearchBarPlacement = .integratedButton
        // In the navigation bar on every device, at the corner beside Select. The toolbar's leading end is the drafts pill's. Set
        // once, before the first layout, so rotating or collapsing can't move the button between bars.
        navigationItem.searchBarPlacementAllowsToolbarIntegration = false
        definesPresentationContext = true
    }

    /// The trailing items while browsing: Select, while there are threads to select, on touch; a desktop window picks
    /// several without a mode. The system places the search button beside it, at the corner. Placed
    /// by hand among these items, the search button's pressed glass outlived its morph into the field and hung under
    /// the field's leading end as a blank capsule until the field took focus.
    private var browsingTrailingItems: [UIBarButtonItem] {
        (viewModel.actions == nil || picksWithPointer ? [] : [select.item])
            + (viewModel.offersFilter ? [filterButton.item] : [])
    }

    /// Called by UIKit whenever an observed view-model property changes.
    public override func updateProperties() {
        super.updateProperties()
        applySections(viewModel.sections)
        showPick()
        updateEmptyState()
        if problemsItem.show(viewModel.problems) { toolbarEndsChanged() }
        showFilter()
        if let categoryButton, let category = viewModel.category {
            Self.update(categoryButton, selected: category, unreadCounts: viewModel.categoryUnreadCounts) {
                [weak self] in self?.show($0)
            }
        }
        if !viewModel.isRefreshing, collectionView.refreshControl?.isRefreshing == true {
            collectionView.refreshControl?.endRefreshing()
        }
    }

    /// Asks about the accounts' sync problems, each with its fix.
    private func explain(_ notices: [AccountProblemNotice]) {
        let alert = UIAlertController.accountProblems(notices) { [weak self] notice in
            guard let self else { return }
            Task { await self.viewModel.fix(notice) }
        }
        present(alert, animated: true)
    }

    /// Only on a change: setting the configuration lays the view out again, which would run this again. Reads the
    /// rows on screen, not the model's, so nothing shows while rows are still going into a box or breaking up. Select
    /// goes with the last row and comes back with the first.
    private func updateEmptyState() {
        // Only a bar showing this list morphs: under a pushed thread, laying the bar out would animate the reader's.
        let bar = navigationController.flatMap { $0.topViewController === self ? $0.navigationBar : nil }
        select.show(rows: dataSource.snapshot().numberOfItems, in: bar)
        let state: EmptyState? =
            !viewModel.hasLoaded || dataSource.snapshot().numberOfItems > 0
            ? nil
            : viewModel.isLoadingOlder
                ? .loading : inboxZeroState() ?? .empty(pointingTo: viewModel.categoryWithUnread)
        guard state != emptyState else { return }
        let previous = emptyState
        emptyState = state
        contentUnavailableConfiguration =
            switch state {
            case nil, .inboxZero: nil
            case .loading: UIContentUnavailableConfiguration.loading()
            case .empty(let other?): pointing(empty, to: other)
            case .empty(nil): empty
            case .filtered(let filter): filteredConfiguration(for: filter)
            }
        showInboxZero(for: state, after: previous)
    }

    /// `configuration` with a link to another category that has unread mail.
    private func pointing(_ configuration: UIContentUnavailableConfiguration, to category: InboxCategory)
        -> UIContentUnavailableConfiguration
    {
        var configuration = configuration
        var button = UIButton.Configuration.plain()
        button.title = String(
            localized: "Go to \(category.title)", table: "Mailbox", bundle: .module,
            comment: "Link from an empty Inbox category to another with unread mail")
        configuration.button = button
        configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.show(category) }
        return configuration
    }

    /// Switches to `category`'s threads, from the top.
    func show(_ category: InboxCategory) {
        viewModel.select(category)
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
    }

    private static func noMail(in mailbox: Mailbox) -> UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: mailbox.symbol)
        configuration.text = String(
            localized: "No Mail", table: "Mailbox", bundle: .module, comment: "An empty mailbox")
        return configuration
    }

    private func configureSwipes() {
        swipes = SwipeActionsController(
            collectionView: collectionView,
            rowID: { [weak self] in self?.dataSource.itemIdentifier(for: $0) },
            indexPath: { [weak self] in self?.dataSource.indexPath(for: $0) })
        swipes.actions = { [weak self] id, side in
            guard let self, !isEditing else { return [] }
            return swipeActions(for: id, on: side)
        }
        swipes.openSettings = { [weak self] in self?.viewModel.openSwipeSettings() }
        swipes.didOpenRow = { [weak self] in self?.hover?.refresh() }
    }

    private func swipeActions(for id: ThreadSummary.ID, on side: SwipeSide) -> [SwipeAction] {
        guard let thread = threadsByID[id] else { return [] }
        return viewModel.swipeActions(for: thread, on: side).map { swipeAction($0, for: id) }
    }

    /// What a swipe button, or a quick action, does to the row `id`.
    func swipeAction(_ button: MailboxViewModel.SwipeButton, for id: ThreadSummary.ID) -> SwipeAction {
        switch button.swipe {
        case .perform(let action):
            SwipeAction(
                title: action.title, symbol: action.symbol, tint: button.tint, color: button.choice.color,
                stow: action.stow
            ) {
                [weak self] stowing in
                guard let self else { return }
                guard let stowing else { return perform(action, on: [id]) }
                stow([id], into: stowing.box, doing: action, then: stowing.done)
            }
        case .snooze:
            SwipeAction(
                title: String(
                    localized: "Snooze", table: "Actions", bundle: .module,
                    comment: "Hides threads until a later time"),
                symbol: "clock", tint: button.tint, color: button.choice.color
            ) { [weak self] _ in self?.askToSnooze(id) }
        }
    }

    /// Asks until when, pointing at the thread's row, then snoozes it.
    private func askToSnooze(_ id: ThreadSummary.ID) {
        guard let indexPath = dataSource.indexPath(for: id), let cell = collectionView.cellForItem(at: indexPath)
        else { return }
        let sheet = UIAlertController.snooze(from: self, source: cell) { [weak self] date in
            self?.lastRemoval = .now
            self?.viewModel.snooze([id], until: date)
        }
        present(sheet, animated: true)
    }

    private func configureDataSource() {
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, ThreadSummary.ID> {
            [weak self] cell, _, id in
            guard let self, let thread = threadsByID[id] else { return }
            cell.accessories = [.multiselect(displayed: .whenEditing)]
            // A row that went into a box left its cell's content hidden.
            cell.contentView.alpha = 1
            cell.contentConfiguration = ThreadRowConfiguration(
                thread: thread,
                dateText: viewModel.dateText(for: thread),
                account: viewModel.rowAccount(for: thread),
                display: display
            )
            // The open thread stays selected beside the list on iPad; a light tint keeps its text readable.
            cell.configurationUpdateHandler = { cell, state in
                var background = UIBackgroundConfiguration.listCell().updated(for: state)
                if state.isSelected || state.isHighlighted {
                    background.backgroundColor = .tintColor.withAlphaComponent(0.14)
                }
                cell.backgroundConfiguration = background.kept(toSafeAreaOf: cell)
            }
            // VoiceOver reaches the swipe actions through the rotor.
            cell.accessibilityCustomActions =
                (swipeActions(for: id, on: .right)
                + swipeActions(for: id, on: .left)).map { action in
                    UIAccessibilityCustomAction(name: action.title) { _ in
                        action.handler(nil)
                        return true
                    }
                }
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] cell, _, indexPath in
            guard let self, let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }
            title(cell, as: section)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, id in
            view.dequeueConfiguredReusableCell(using: row, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { view, _, indexPath in
            view.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    private func title(_ header: UICollectionViewListCell, as section: MailboxSection) {
        var content = UIListContentConfiguration.header()
        content.text = sectionTitles[section]
        header.contentConfiguration = content
        header.backgroundConfiguration = .pinnedHeader(in: header)
    }

    private func applySections(_ sections: [MailboxViewModel.Section]) {
        guard case .free = listMotion else { return }
        var snapshot = NSDiffableDataSourceSnapshot<MailboxSection, ThreadSummary.ID>()
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
        if dissolveDeleted(leaving: threads) { return }
        threadsByID = threads
        let retitled = sectionTitles.update(to: sections)
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        // Headers are retitled in place. Reloading their sections would reload every row in them too, and a row
        // reloaded while a gap above it closes and select mode ends could be left blurred mid-crossfade.
        for section in retitled {
            guard let index = dataSource.index(for: section) else { continue }
            let header = collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: index))
            if let header = header as? UICollectionViewListCell { title(header, as: section) }
        }
        swipes.rowsDidChange()
        hover?.refresh()
        markOpenThread()
        // Selected threads may have left the list.
        if isEditing { updateSelectionChrome() }
    }
}

// MARK: - Deleting

extension MailboxViewController {
    /// Performs `action`, then `done`. Delete Forever asks first, and on Cancel does neither.
    func perform(_ action: ThreadAction, on ids: [ThreadSummary.ID], then done: @escaping () -> Void = {}) {
        guard action == .deleteForever else {
            lastRemoval = .now
            viewModel.perform(action, on: ids)
            return done()
        }
        let everything = viewModel.isTrash && ids.count == dataSource.snapshot().numberOfItems
        let alert = UIAlertController.deleteForever(everything ? .trash(ids.count) : .threads(ids.count)) {
            [weak self] in
            guard let self else { return }
            let now = ContinuousClock.now
            for id in ids { deleted[id] = now }
            lastRemoval = now
            viewModel.perform(.deleteForever, on: ids)
            done()
        }
        present(alert, animated: true)
    }

    /// Breaks the rows of threads deleted forever that are leaving the list into dust and holds the list still while
    /// it blows clear. With Reduce Motion on, they fade out with the list's own deletion instead. Returns whether any
    /// row dissolves, in which case the list takes this change once the hold ends.
    private func dissolveDeleted(leaving threads: [ThreadSummary.ID: ThreadSummary]) -> Bool {
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

extension MailboxViewController: UICollectionViewDelegate {
    /// How close to the last row the next older page is requested, so it arrives before the user gets there.
    private static let loadOlderLead = 20

    public func collectionView(
        _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        if let id = dataSource.itemIdentifier(for: indexPath) { viewModel.readAhead([id], because: .visible) }
        let snapshot = dataSource.snapshot()
        guard let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }
        let before = snapshot.sectionIdentifiers.prefix { $0 != section }
            .reduce(0) { $0 + snapshot.numberOfItems(inSection: $1) }
        guard snapshot.numberOfItems - (before + indexPath.item) <= Self.loadOlderLead else { return }
        Task { [viewModel] in await viewModel.loadOlderIfNeeded() }
    }

    public func collectionView(
        _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        swipes.cellDidEndDisplaying(cell)
        hover?.cellDidEndDisplaying(cell)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        swipes.close()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        hover?.refresh()
        placeInboxZero()
    }

    public func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        placeInboxZero()
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        // A tap while actions are open just closes them. A desktop window's clicks pick through the view model.
        !picksWithPointer && !swipes.close()
    }

    /// A row held under the finger is likely to open, so its bodies start downloading before the tap ends.
    public func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        guard !isEditing, let id = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.readAhead([id], because: .touched)
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isEditing {
            reportTouchPick()
            return updateSelectionChrome()
        }
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        // Search results sit outside the navigation stack, so they never see the reader close to deselect then.
        if navigationController == nil { collectionView.deselectItem(at: indexPath, animated: true) }
        reportTouchPick()
        viewModel.open(id)
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard isEditing else { return }
        reportTouchPick()
        updateSelectionChrome()
    }

    public func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        if picksWithPointer { return pointerMenu(at: point, fallback: indexPaths) }
        guard !isEditing, indexPaths.count == 1, let id = indexPaths.first.flatMap(dataSource.itemIdentifier(for:)),
            let thread = threadsByID[id]
        else { return nil }
        swipes.close()
        return ThreadMenu.configuration(for: thread, viewModel: viewModel, presenter: self) { [weak self] in
            self?.perform($0, on: [id])
        }
    }

    /// Tapping the preview opens the thread it shows.
    public func collectionView(
        _ collectionView: UICollectionView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating
    ) {
        guard let id = (configuration.identifier as? ThreadMenu.Identifier)?.thread else { return }
        animator.addCompletion { [weak self] in self?.viewModel.open(id) }
    }
}

extension MailboxViewController {
    private func configureDrag() {
        guard
            let carry = ConversationCarry(
                style: viewModel.interaction, window: { [viewModel] in viewModel.newWindow(for: $0) },
                sources: viewModel.conversationSources, supportsWindows: UIApplication.shared.supportsMultipleScenes)
        else { return }
        let drag = ConversationDrag(
            threads: { [weak self] indexPath in
                guard let self, !isEditing, let id = dataSource.itemIdentifier(for: indexPath) else { return [] }
                let ids = picksWithPointer ? viewModel.menuTargets(for: id) : [id]
                return ids.compactMap { self.threadsByID[$0] }
            },
            carry: carry, mailbox: viewModel.mailbox, willBegin: { [weak self] in self?.swipes.close() })
        self.drag = drag
        collectionView.dragDelegate = drag
    }
}

// MARK: - Selecting several threads

extension MailboxViewController {
    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        swipes.close(animated: animated)
        collectionView.isEditing = editing
        reportTouchPick()
        // Selecting has no search; the system takes its button away with the controller.
        navigationItem.searchController = editing ? nil : search
        navigationItem.rightBarButtonItems =
            editing
            ? [
                UIBarButtonItem(
                    systemItem: .done,
                    primaryAction: UIAction { [weak self] _ in self?.setEditing(false, animated: true) })
            ]
            : browsingTrailingItems
        if editing {
            updateSelectionChrome()
        } else {
            navigationItem.leftBarButtonItems = browsingLeadingItems
            title = viewModel.title
            setToolbarItems(browsingToolbarItems, animated: animated)
        }
        toolbarEndsChanged()
    }

    /// The picked threads, as the view model holds them.
    var selectedIDs: [ThreadSummary.ID] { viewModel.selectedIDs }

    /// The leading items while browsing: the sidebar button when the mailboxes are behind this list, then the
    /// category menu.
    private var browsingLeadingItems: [UIBarButtonItem] {
        [sidebarBackItem(), categoryItem].compactMap(\.self)
    }

    /// The title, Select All and the toolbar's actions, for what is selected now.
    private func updateSelectionChrome() {
        let ids = selectedIDs
        let snapshot = dataSource.snapshot()
        let allSelected = !ids.isEmpty && ids.count == snapshot.numberOfItems
        title =
            ids.isEmpty
            ? viewModel.title
            : String(
                localized: "\(ids.count) Selected", table: "Mailbox", bundle: .module,
                comment: "Title while selecting threads")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: allSelected
                ? String(localized: "Deselect All", table: "Mailbox", bundle: .module, comment: "Clears the selection")
                : String(
                    localized: "Select All", table: "Mailbox", bundle: .module,
                    comment: "Selects every thread in the list"),
            primaryAction: UIAction { [weak self] _ in self?.selectEveryRow(!allSelected) })

        // With nothing selected, show what the list as a whole allows, disabled, so the toolbar doesn't jump.
        let threads = (ids.isEmpty ? snapshot.itemIdentifiers : ids).compactMap { threadsByID[$0] }
        let actions = MailboxViewModel.bulkActions(for: threads, in: viewModel.mailbox)
        // What takes the threads out of the way is what selecting is most for, so it's the last to fold into More.
        let away = threads.first.map { ThreadPlace($0, in: viewModel.mailbox).awayActions } ?? []
        let items = actions.map { action in
            // With nothing selected, Trash's Delete Forever empties it.
            let emptiesTrash = action == .deleteForever && ids.isEmpty && viewModel.isTrash
            // Words, not the symbol, since it does more than the selected-threads button it replaces.
            let item = UIBarButtonItem(
                title: emptiesTrash ? DeleteForeverScope.trash(0).actionTitle : action.title,
                image: emptiesTrash ? nil : UIImage(systemName: action.symbol),
                primaryAction: UIAction { [weak self] _ in
                    guard let self else { return }
                    performOnSelection(action, all: emptiesTrash)
                })
            item.isEnabled = !ids.isEmpty || emptiesTrash
            if away.contains(action) { item.visibilityPriority = .high }
            return item
        }
        // Labels belong to an account, so the picker opens for one account's threads at a time.
        let labels = UIBarButtonItem.changeLabels { [weak self] in
            guard let self else { return }
            viewModel.changeLabels(of: selectedIDs)
            setEditing(false, animated: true)
        }
        labels.isEnabled = Set(threads.map(\.id.accountID)).count == 1 && !ids.isEmpty
        let move = UIBarButtonItem.move { [weak self] in
            guard let self else { return }
            viewModel.move(selectedIDs)
            setEditing(false, animated: true)
        }
        move.isEnabled = !ids.isEmpty
        let snooze = UIBarButtonItem.snooze(from: self) { [weak self] date in
            guard let self else { return }
            viewModel.snooze(selectedIDs, until: date)
            setEditing(false, animated: true)
        }
        snooze.isEnabled = !ids.isEmpty && MailboxViewModel.canSnooze(threads)
        let pin = viewModel.pinning(threads.map(\.id)).map { pin in
            let item = UIBarButtonItem.pin(pin) { [weak self] in
                guard let self else { return }
                viewModel.pin(selectedIDs, pin)
                setEditing(false, animated: true)
            }
            item.isEnabled = !ids.isEmpty
            return item
        }
        // Trash leaves out labels, snooze and pins, which mean nothing there, so its Delete Forever fits without More.
        let organize = viewModel.isTrash ? [move] : [labels, move, snooze] + [pin].compactMap(\.self)
        setToolbarItems(Array(items.prefix(1)) + organize + [.flexibleSpace()] + items.dropFirst(), animated: false)
    }

    private func selectEveryRow(_ select: Bool) {
        for item in dataSource.snapshot().itemIdentifiers {
            guard let indexPath = dataSource.indexPath(for: item) else { continue }
            if select {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            } else {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
        reportTouchPick()
        updateSelectionChrome()
    }

    /// Performs `action` on the selected threads, or with `all` on every one in the list, and stops selecting.
    private func performOnSelection(_ action: ThreadAction, all: Bool = false) {
        let ids = all ? dataSource.snapshot().itemIdentifiers : selectedIDs
        guard let kind = action.stow, Motion.playsRemovals, let window = view.window else {
            return perform(action, on: ids) { [weak self] in self?.setEditing(false, animated: true) }
        }
        // The action's button may be in the toolbar's overflow menu, so a box pops up above the toolbar to take them.
        let badge = StowBadgeView(kind: kind)
        // Well above the toolbar and the confirmation that shows over it, still within reach of the lower rows, and
        // off iPhone Duo's fold.
        badge.show(at: CGPoint(x: window.foldLane.midX, y: window.bounds.height * 0.72), in: window)
        stow(ids, into: badge.box, doing: action) { [weak self] in
            badge.dismiss()
            self?.setEditing(false, animated: true)
        }
        // Their rows lose the selection tint once lifted off, so no tinted gaps are left behind.
        for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
    }
}

// MARK: - The undo toast

extension MailboxViewController: UndoToastLane {
    /// Browsing, the toolbar holds the drafts pill, while it shows, and Compose at its ends, and the account status
    /// between them when an account has a problem. Selecting fills it with actions.
    var toolbarEnds: [UIBarButtonItem] {
        guard !isEditing, problemsItem.item.isHidden else { return [] }
        return browsingEnds.filter { !$0.isHidden }
    }
}

// MARK: - Putting threads away

extension MailboxViewController {
    /// Does `action` on `ids` and flies the rows on screen into `box`, holding the list still meanwhile. Once they
    /// are in, `finish` runs and the list closes the gaps. Off screen, or while other rows are still going in, the
    /// action just happens.
    private func stow(
        _ ids: [ThreadSummary.ID], into box: StowBoxView, doing action: ThreadAction,
        then finish: @escaping () -> Void
    ) {
        lastRemoval = .now
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
