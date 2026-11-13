import MailCore
import UIKit

/// The mailboxes, then the user's labels, or each account's when there are several. In a narrow window it is the root,
/// with the Inbox open on top of it at launch; in a wide one it is the sidebar, keeping the open mailbox selected.
public final class MailboxesViewController: UIViewController {
    public enum Style {
        case list
        case sidebar
    }

    private let viewModel: MailboxesViewModel
    private let style: Style
    /// What is shown beside the sidebar, kept selected in it.
    public var selected: MailboxesViewModel.Destination? {
        didSet { selectShownMailbox() }
    }
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<MailboxesViewModel.Section, MailboxesViewModel.Item>!
    private var observation: Task<Void, Never>?

    public init(viewModel: MailboxesViewModel, style: Style = .list) {
        self.viewModel = viewModel
        self.style = style
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
        var list = UICollectionLayoutListConfiguration(appearance: style == .sidebar ? .sidebar : .insetGrouped)
        list.headerMode = .supplementary
        collectionView = UICollectionView(
            frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: list))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.accessibilityIdentifier = "mailboxes"
        collectionView.delegate = self
        view.addSubview(collectionView)
        configureDataSource()
        toolbarItems = [
            UIBarButtonItem(
                title: String(localized: "Settings", bundle: .module, comment: "Title of the settings screen"),
                image: UIImage(systemName: "gearshape"),
                primaryAction: UIAction { [weak self] _ in self?.viewModel.openSettings() }),
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
        if style == .list {
            for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
                collectionView.deselectItem(at: indexPath, animated: animated)
            }
        }
        navigationController?.setToolbarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        wear(viewModel.theme)
    }

    /// Called by UIKit whenever an observed view-model property changes.
    public override func updateProperties() {
        super.updateProperties()
        var snapshot = NSDiffableDataSourceSnapshot<MailboxesViewModel.Section, MailboxesViewModel.Item>()
        for group in viewModel.groups {
            snapshot.appendSections([group.section])
            snapshot.appendItems(group.items, toSection: group.section)
        }
        dataSource.apply(snapshot, animatingDifferences: collectionView.window != nil)
        selectShownMailbox()
    }

    private func selectShownMailbox() {
        guard style == .sidebar, let dataSource else { return }
        let item = dataSource.snapshot().itemIdentifiers.first { $0.destination == selected }
        guard let indexPath = item.flatMap(dataSource.indexPath(for:)) else { return }
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
    }

    private func configureDataSource() {
        let style = style
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, MailboxesViewModel.Item> {
            cell, _, item in
            var content =
                style == .sidebar ? UIListContentConfiguration.sidebarCell() : UIListContentConfiguration.cell()
            content.text = item.title
            content.image = UIImage(systemName: item.symbol)
            content.imageProperties.tintColor = UIColor(labelColor: item.color) ?? .tintColor
            cell.contentConfiguration = content
            var accessories: [UICellAccessory] = style == .sidebar ? [] : [.disclosureIndicator()]
            if item.count > 0 {
                accessories.insert(.label(text: item.count.formatted()), at: 0)
            }
            cell.accessories = accessories
            cell.accessibilityIdentifier =
                switch item.destination {
                case .mailbox(let mailbox):
                    "mailbox.\(mailbox.labelID ?? "all")" + (mailbox.accountID.map { ".\($0.rawValue)" } ?? "")
                case .scheduled: "mailbox.scheduled"
                case .snoozed: "mailbox.snoozed"
                }
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            var content = style == .sidebar ? UIListContentConfiguration.sidebarHeader() : .header()
            switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
            case .mailboxes, nil: break
            case .labels:
                content.text = String(localized: "Labels", bundle: .module, comment: "Header above the user's labels")
            case .account(let account):
                // The account's own color, beside its address: the one place it shows in a view of every account.
                content.text = account.email
                content.image = UIImage(systemName: "circle.fill")
                content.imageProperties.tintColor = account.color.uiColor
                content.imageProperties.maximumSize = CGSize(width: 10, height: 10)
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
        viewModel.open(item.destination)
    }
}
