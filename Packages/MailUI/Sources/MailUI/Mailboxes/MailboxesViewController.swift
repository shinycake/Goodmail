import MailCore
public import UIKit

/// The mailboxes, then the user's labels, or each account's when there are several. In a narrow window it is the root,
/// with the Inbox open on top of it at launch; in a wide one it is the sidebar, keeping the open mailbox selected.
public final class MailboxesViewController: UIViewController {
    public enum Style {
        case list
        case sidebar
    }

    let viewModel: MailboxesViewModel
    let style: Style
    /// What is shown beside the sidebar, kept selected in it.
    public var selected: MailboxesViewModel.Destination? {
        didSet { selectShownMailbox() }
    }
    private(set) var collectionView: UICollectionView!
    /// The faint doodles behind the list, which a sidebar goes without.
    private(set) var doodles: MailboxesDoodlesModel?
    private(set) var dataSource: UICollectionViewDiffableDataSource<MailboxesViewModel.Section, SidebarRow>!
    /// Which sections the reader folded in a sidebar, kept on this device.
    let foldedSections: FoldedSections
    /// Each section's unread threads, which its header shows while folded.
    var sectionUnread: [MailboxesViewModel.Section: Int] = [:]
    /// How mail is coming in, for a desktop sidebar's footer.
    let syncFooter: SyncFooterSource?
    /// The footer under a desktop sidebar, in place of its toolbar.
    var footer: SidebarFooterView?
    private var observation: Task<Void, Never>?
    /// Takes dragged conversations onto the rows. The list's drop delegate, which it doesn't keep.
    private var mailDrop: SidebarDrop?
    /// Each account's label changes, made when first needed.
    private var labelFlows: [AccountID: LabelEditFlow] = [:]
    /// Renames and deletes smart mailboxes, made when first needed; `nil` where they can't be changed.
    private(set) lazy var smartMailboxFlow = viewModel.smartMailboxStore.map {
        SmartMailboxFlow(store: $0, presenter: { [weak self] in self })
    }

    /// `syncFooter` is what a desktop sidebar says under its rows about mail coming in.
    public init(
        viewModel: MailboxesViewModel, style: Style = .list, foldedSections: FoldedSections = FoldedSections(),
        syncFooter: SyncFooterSource? = nil
    ) {
        self.viewModel = viewModel
        self.style = style
        self.foldedSections = foldedSections
        self.syncFooter = syncFooter
        super.init(nibName: nil, bundle: nil)
        title = Self.title
        navigationItem.largeTitleDisplayMode = .always
        // From the start, not once the view loads: a narrow window's mailboxes sit under the list unseen, and the
        // window's title still names a label or smart mailbox from what they follow (`namesChanged`).
        observation = Task { [viewModel] in await viewModel.observe() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    static var title: String {
        String(localized: "Mailboxes", table: "Mailboxes", bundle: .module, comment: "Title of the list of mailboxes")
    }

    deinit {
        observation?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.accessibilityIdentifier = "mailboxes"
        collectionView.delegate = self
        // Settings and New Label float over the rows as glass buttons of their own, with no frosted band under them
        // as a sidebar's toolbar gets on a Mac or an iPad.
        collectionView.bottomEdgeEffect.isHidden = true
        view.addSubview(collectionView)
        configureDataSource()
        let mailDrop = SidebarDrop(
            viewModel: viewModel,
            destination: { [weak self] in self?.dataSource.itemIdentifier(for: $0)?.item?.destination })
        self.mailDrop = mailDrop
        collectionView.dropDelegate = mailDrop
        if style == .list {
            let doodles = MailboxesDoodlesModel()
            installDoodles(doodles)
            self.doodles = doodles
        }
        let settings = UIBarButtonItem(
            title: String(
                localized: "Settings", table: "Mailboxes", bundle: .module, comment: "Title of the settings screen"),
            image: UIImage(systemName: "gearshape"),
            primaryAction: UIAction { [weak self] _ in self?.viewModel.openSettings() })
        let compose = UIBarButtonItem(
            title: String(localized: "New Message", table: "Mailboxes", bundle: .module, comment: "Composer title"),
            image: UIImage(systemName: "square.and.pencil"),
            primaryAction: UIAction { [weak self] _ in self?.viewModel.compose() })
        // New Message is the last to go into More when the toolbar runs short, as in a bar down iPhone Duo's side.
        compose.visibilityPriority = .high
        // As a sidebar beside the list, New Message is the list's alone, so the window has one.
        let ownCompose = style == .list ? [compose] : []
        toolbarItems = [settings, .flexibleSpace()] + [newLabelItem()].compactMap(\.self) + ownCompose
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if style == .list {
            for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
                collectionView.deselectItem(at: indexPath, animated: animated)
            }
        }
        navigationController?.setToolbarHidden(showsFooter, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        installFooter()
        wear(viewModel.theme)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeDoodles()
    }

    /// Called by UIKit whenever an observed view-model property changes.
    public override func updateProperties() {
        super.updateProperties()
        let groups = viewModel.groups
        let sections = groups.map(\.section)
        // Only a change of sections, as an account added, replaces the rows; otherwise each section's rows are
        // diffed in place, keeping what the reader folded.
        if dataSource.snapshot().sectionIdentifiers != sections {
            var snapshot = NSDiffableDataSourceSnapshot<MailboxesViewModel.Section, SidebarRow>()
            snapshot.appendSections(sections)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        let animated = collectionView.window != nil
        for group in groups {
            dataSource.apply(sectionSnapshot(of: group), to: group.section, animatingDifferences: animated)
        }
        updateFoldedCounts(groups)
        if let footer, let syncFooter { footer.show(syncFooter.status) }
        selectShownMailbox()
    }

    /// The group's rows with their nested labels, unfolded unless the reader folded them (`MailboxesViewModel.folded`).
    /// In a sidebar they hang under the section's header row, which folds them all, as the reader last left it.
    private func sectionSnapshot(
        of group: MailboxesViewModel.Group
    ) -> NSDiffableDataSourceSectionSnapshot<SidebarRow> {
        var section = NSDiffableDataSourceSectionSnapshot<SidebarRow>()
        func append(_ items: [MailboxesViewModel.Item], to parent: SidebarRow?) {
            section.append(items.map(SidebarRow.mailbox), to: parent)
            for item in items {
                guard let children = group.children[item.destination] else { continue }
                append(children, to: .mailbox(item))
                if !viewModel.folded.contains(item.destination) { section.expand([.mailbox(item)]) }
            }
        }
        if foldsSections(group.section) {
            let header = SidebarRow.header(group.section)
            section.append([header])
            append(group.items, to: header)
            let isFolded = foldedSections.isFolded(group.section)
            if !isFolded { section.expand([header]) }
            viewModel.show(group.section, folded: isFolded)
        } else {
            append(group.items, to: nil)
            viewModel.show(group.section, folded: false)
        }
        return section
    }

    /// Folds or unfolds a parent's labels, as tapping a folder that is no label does.
    func toggle(_ row: SidebarRow, at indexPath: IndexPath) {
        guard let sectionID = dataSource.sectionIdentifier(for: indexPath.section) else { return }
        var section = dataSource.snapshot(for: sectionID)
        let folds = section.isExpanded(row)
        if folds { section.collapse([row]) } else { section.expand([row]) }
        remember(row, folded: folds)
        dataSource.apply(section, to: sectionID, animatingDifferences: true)
    }

    private func selectShownMailbox() {
        guard style == .sidebar, let dataSource else { return }
        let row = dataSource.snapshot().itemIdentifiers.first { $0.item?.destination == selected }
        guard let indexPath = row.flatMap(dataSource.indexPath(for:)) else { return }
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
    }

    /// What the icons of the rows in `indexPath`'s section wear.
    private func theme(at indexPath: IndexPath) -> Theme? {
        dataSource.sectionIdentifier(for: indexPath.section).map(viewModel.theme(of:))
    }

    private func configureDataSource() {
        let style = style
        let mailboxRow = UICollectionView.CellRegistration<UICollectionViewListCell, MailboxesViewModel.Item> {
            [weak self] cell, indexPath, item in
            let isParent = item.isParent
            let theme = self?.theme(at: indexPath)
            // A level of nesting reads at a glance in the list, as it does in the sidebar.
            if style == .list { cell.indentationWidth = 20 }
            // Folded away, a parent counts its nested labels' unread threads with its own.
            cell.configurationUpdateHandler = { cell, state in
                guard let cell = cell as? UICollectionViewListCell else { return }
                let shown = isParent && !state.isExpanded ? item.nestedCount : item.count
                let count = shown > 0 ? shown.formatted() : nil
                // `cell()` takes the sidebar's look by itself in a sidebar list (iOS 18).
                var content = style == .sidebar ? UIListContentConfiguration.cell() : .valueCell()
                content.text = item.title
                // A gradient is drawn into a plain image, which the cell neither sizes nor gives a symbol's slot, so
                // every icon is sized here, as the cell sizes a symbol, and sits in the same slot.
                // As the cell sizes a tinted symbol: to the body text style, at the large scale, or the small one at
                // accessibility sizes, where icons grow far less than the text.
                let size = UIImage.SymbolConfiguration(
                    textStyle: .body,
                    scale: state.traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .small : .large)
                content.imageProperties.preferredSymbolConfiguration = size
                content.imageProperties.reservedLayoutSize = CGSize(
                    width: UIListContentConfiguration.ImageProperties.standardDimension,
                    height: UIListContentConfiguration.ImageProperties.standardDimension)
                let symbol = UIImage(
                    systemName: item.symbol, withConfiguration: size.withTraitCollection(state.traitCollection))
                // A label's own color, or the section's: an account's color, or the gradient across each icon.
                content.image =
                    if let color = UIColor(labelColor: item.color) {
                        symbol?.withTintColor(color, renderingMode: .alwaysOriginal)
                    } else if let symbol, let theme {
                        theme.paint(
                            symbol, in: state.traitCollection, direction: cell.effectiveUserInterfaceLayoutDirection)
                    } else {
                        symbol
                    }
                let unfold: [UICellAccessory] = isParent ? [.outlineDisclosure()] : []
                switch style {
                case .sidebar:
                    cell.accessories = (count.map { [.label(text: $0)] } ?? []) + unfold
                case .list:
                    // The count is the value cell's secondary text, not an accessory, so at accessibility sizes it
                    // moves under the name instead of squeezing it until words break.
                    content.secondaryText = count
                    cell.accessories = unfold.isEmpty ? [.disclosureIndicator()] : unfold
                }
                cell.contentConfiguration = content
            }
            cell.accessibilityIdentifier =
                switch item.destination {
                case .mailbox(let mailbox):
                    "mailbox.\(mailbox.labelID ?? "all")" + (mailbox.accountID.map { ".\($0.rawValue)" } ?? "")
                case .scheduled: "mailbox.scheduled"
                case .snoozed: "mailbox.snoozed"
                case .folder(let path, let account): "mailbox.folder.\(path).\(account.rawValue)"
                case .smart(let id): "mailbox.smart.\(id.rawValue)"
                }
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            let section = self?.dataSource.sectionIdentifier(for: indexPath.section)
            header.contentConfiguration = section.map(Self.headerContent) ?? UIListContentConfiguration.header()
        }
        let headerRow = foldingHeaderRegistration()
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView, indexPath, row in
            switch row {
            case .header(let section):
                collectionView.dequeueConfiguredReusableCell(using: headerRow, for: indexPath, item: section)
            case .mailbox(let item):
                collectionView.dequeueConfiguredReusableCell(using: mailboxRow, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        // Rows and sections folded with their disclosure button.
        dataSource.sectionSnapshotHandlers.willExpandItem = { [weak self] row in self?.remember(row, folded: false) }
        dataSource.sectionSnapshotHandlers.willCollapseItem = { [weak self] row in self?.remember(row, folded: true) }
    }
}

extension MailboxesViewController: UICollectionViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        placeDoodles()
    }

    public func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        placeDoodles()
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath)?.item else { return }
        viewModel.open(item.destination)
    }

    /// A section's header and a folder that is no label open nothing: a click folds or unfolds it, and the sidebar
    /// keeps the shown mailbox selected.
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch row {
        case .header:
            toggle(row, at: indexPath)
            return false
        case .mailbox(let item):
            guard case .folder = item.destination else { return true }
            toggle(row, at: indexPath)
            return false
        }
    }

    /// Rename and Delete on a user label, on a folder that only holds labels, or on a smart mailbox.
    public func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first else { return nil }
        if let menu = smartMailboxMenu(for: dataSource.itemIdentifier(for: indexPath)?.item) { return menu }
        guard let edits = labelEdits(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: [
                UIAction(title: edits.renameTitle, image: UIImage(systemName: "pencil")) { _ in edits.rename() },
                UIAction(title: edits.deleteTitle, image: UIImage(systemName: "trash"), attributes: .destructive) {
                    _ in edits.delete()
                },
            ])
        })
    }
}

/// Renaming and deleting the user label a row shows, or the labels in a folder that is no label, from its context
/// menu or a swipe.
private struct LabelEdits {
    /// What the row is, which names the context menu's actions.
    enum Target {
        case label, folder
    }

    /// The shorter names a swipe has room for, the alerts' own buttons.
    static let swipeRenameTitle = String(
        localized: "Rename", table: "LabelEditing", bundle: .module, comment: "Button: renames the label")
    static let swipeDeleteTitle = String(
        localized: "Delete", table: "LabelEditing", bundle: .module, comment: "Button: deletes the label")

    let target: Target
    let rename: () -> Void
    /// Asks first, as every delete of a label does.
    let delete: () -> Void

    var renameTitle: String {
        switch target {
        case .label:
            String(
                localized: "Rename Label", table: "LabelEditing", bundle: .module,
                comment: "Action: renames the label, and the title of the alert that names it")
        case .folder:
            String(
                localized: "Rename Folder", table: "LabelEditing", bundle: .module,
                comment: "Action: renames a folder that only holds labels, with the labels in it")
        }
    }

    var deleteTitle: String {
        switch target {
        case .label:
            String(
                localized: "Delete Label", table: "LabelEditing", bundle: .module, comment: "Action: deletes the label")
        case .folder:
            String(
                localized: "Delete Folder", table: "LabelEditing", bundle: .module,
                comment: "Action: deletes a folder that only holds labels, with the labels in it")
        }
    }
}

extension MailboxesViewController {
    /// What can change the label at a row, or the labels in a folder that is no label; `nil` for the standard
    /// mailboxes.
    private func labelEdits(at indexPath: IndexPath) -> LabelEdits? {
        guard let item = dataSource.itemIdentifier(for: indexPath)?.item else { return nil }
        if let group = viewModel.labelGroup(at: item.destination), let flow = labelFlow(for: group.accountID) {
            return LabelEdits(
                target: .folder, rename: { flow.rename(group) },
                delete: { [weak self, viewModel] in
                    let leaves = viewModel.group(group, holds: self?.selected)
                    flow.delete(group) { if leaves { self?.leaveDeletedLabel() } }
                })
        }
        guard let label = viewModel.label(at: item.destination), let account = label.mailbox.accountID,
            let labelID = label.mailbox.labelID, let flow = labelFlow(for: account)
        else { return nil }
        return LabelEdits(
            target: .label, rename: { flow.rename(labelID, named: label.name) },
            delete: { [weak self, viewModel] in
                flow.delete(labelID, named: label.name, nested: viewModel.nestedLabelCount(in: label)) {
                    self?.leave(item.destination)
                }
            })
    }

    /// Delete, then Rename, swiped in from a user label's trailing edge. Each goes on in its alert; Delete reports
    /// itself undone, since the row stays until the service has deleted the label.
    func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let edits = labelEdits(at: indexPath) else { return nil }
        let delete = UIContextualAction(style: .destructive, title: LabelEdits.swipeDeleteTitle) { _, _, done in
            edits.delete()
            done(false)
        }
        delete.image = UIImage(systemName: "trash")
        let rename = UIContextualAction(style: .normal, title: LabelEdits.swipeRenameTitle) { _, _, done in
            edits.rename()
            done(true)
        }
        rename.image = UIImage(systemName: "pencil")
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }
}

extension MailboxesViewController {
    /// New Label in the toolbar: straight to its name with one account, or a menu of accounts first with several.
    func newLabelItem() -> UIBarButtonItem? {
        let accounts = viewModel.labelAccounts
        guard let first = accounts.first else { return nil }
        let title = LabelEditFlow.newLabel
        let image = UIImage(systemName: "folder.badge.plus")
        guard accounts.count > 1 else {
            return UIBarButtonItem(
                title: title, image: image,
                primaryAction: UIAction { [weak self] _ in self?.labelFlow(for: first.id)?.create { _ in } })
        }
        let menu = UIMenu(
            title: title,
            children: accounts.map { account in
                UIAction(
                    title: account.title, subtitle: account.nickname.map { _ in account.email },
                    image: account.service.markImage
                ) { [weak self] _ in
                    self?.labelFlow(for: account.id)?.create { _ in }
                }
            })
        return UIBarButtonItem(title: title, image: image, menu: menu)
    }

    func labelFlow(for account: AccountID) -> LabelEditFlow? {
        if let flow = labelFlows[account] { return flow }
        guard let editor = viewModel.labelEditor(account) else { return nil }
        let flow = LabelEditFlow(editor: editor, presenter: self)
        labelFlows[account] = flow
        return flow
    }

    /// After its label or smart mailbox is deleted, the sidebar stops showing a mailbox that no longer exists.
    func leave(_ destination: MailboxesViewModel.Destination) {
        guard style == .sidebar, selected == destination else { return }
        viewModel.open(.mailbox(.inbox))
    }

    /// After the labels in a folder are deleted, the sidebar stops showing the one it showed.
    private func leaveDeletedLabel() {
        guard style == .sidebar else { return }
        viewModel.open(.mailbox(.inbox))
    }
}
