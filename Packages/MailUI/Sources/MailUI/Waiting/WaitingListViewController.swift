import MailCore
import UIKit

/// One thing waiting for its time: a scheduled message or a snoozed thread.
nonisolated public struct WaitingRow<ID: Hashable & Sendable>: Hashable, Identifiable, Sendable {
    public let id: ID
    public let title: String
    public let subtitle: String
    /// When its time comes.
    public let time: String
    /// Its account, shown only when there is more than one.
    public let accountColor: AccountColor?
}

public enum WaitingContent<ID: Hashable & Sendable>: Equatable {
    /// The store hasn't been read yet, so an empty list isn't mistaken for nothing waiting.
    case loading
    case loaded([WaitingRow<ID>])
}

/// What a list of waiting things shows and does.
@MainActor
public protocol WaitingListModel: AnyObject, Observable {
    associatedtype ID: Hashable & Sendable
    var content: WaitingContent<ID> { get }
    /// Follows the store until the calling task is cancelled.
    func observe() async
    func open(_ id: ID)
    /// Stops it waiting: back to Drafts, or back to the Inbox.
    func takeBack(_ id: ID)
}

/// The words and symbols a waiting list is shown with.
public struct WaitingListStyle {
    var title: String
    var emptySymbol: String
    var emptyText: String
    var emptyHint: String
    var footer: String?
    var openTitle: String
    var openSymbol: String
    var takeBackTitle: String
    var takeBackSymbol: String
    var accessibilityIdentifier: String
}

/// Things waiting for their time, soonest first. Tapping one opens it; swiping takes it back.
public final class WaitingListViewController<Model: WaitingListModel>: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable {
        case rows
    }

    private let viewModel: Model
    private let style: WaitingListStyle
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, WaitingRow<Model.ID>>!
    private var observation: Task<Void, Never>?

    public init(viewModel: Model, style: WaitingListStyle) {
        self.viewModel = viewModel
        self.style = style
        super.init(nibName: nil, bundle: nil)
        title = style.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    deinit {
        observation?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.footerMode = style.footer == nil ? .none : .supplementary
        list.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, let row = dataSource.itemIdentifier(for: indexPath) else { return nil }
            return UISwipeActionsConfiguration(actions: [takeBackAction(for: row.id)])
        }
        collectionView = UICollectionView(
            frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: list))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.accessibilityIdentifier = style.accessibilityIdentifier
        collectionView.delegate = self
        view.addSubview(collectionView)
        configureDataSource()
        observation = Task { [viewModel] in await viewModel.observe() }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        navigationItem.leftBarButtonItem = sidebarBackItem()
        navigationItem.hidesBackButton = navigationItem.leftBarButtonItem != nil
    }

    /// Called by UIKit whenever an observed view-model property changes.
    public override func updateProperties() {
        super.updateProperties()
        var snapshot = NSDiffableDataSourceSnapshot<Section, WaitingRow<Model.ID>>()
        switch viewModel.content {
        case .loading:
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        case .loaded(let rows) where rows.isEmpty:
            contentUnavailableConfiguration = nothingWaiting
        case .loaded(let rows):
            contentUnavailableConfiguration = nil
            snapshot.appendSections([.rows])
            snapshot.appendItems(rows)
        }
        dataSource.apply(snapshot, animatingDifferences: collectionView.window != nil)
    }

    private var nothingWaiting: UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: style.emptySymbol)
        configuration.text = style.emptyText
        configuration.secondaryText = style.emptyHint
        return configuration
    }

    private func takeBackAction(for id: Model.ID) -> UIContextualAction {
        let action = UIContextualAction(style: .normal, title: style.takeBackTitle) { [weak self] _, _, done in
            self?.viewModel.takeBack(id)
            done(true)
        }
        action.image = UIImage(systemName: style.takeBackSymbol)
        return action
    }

    private func configureDataSource() {
        let identifier = style.accessibilityIdentifier
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, WaitingRow<Model.ID>> {
            cell, indexPath, row in
            var content = UIListContentConfiguration.subtitleCell()
            content.text = row.title
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryText = row.subtitle
            content.secondaryTextProperties.color = .secondaryLabel
            content.textToSecondaryTextVerticalPadding = 4
            cell.contentConfiguration = content
            var time = UICellAccessory.LabelOptions()
            time.font = .preferredFont(forTextStyle: .subheadline)
            time.tintColor = row.accountColor?.uiColor ?? .secondaryLabel
            cell.accessories = [.label(text: row.time, options: time)]
            cell.accessibilityIdentifier = "\(identifier).\(indexPath.item)"
        }
        let footerText = style.footer
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { footer, _, _ in
            var content = UIListContentConfiguration.footer()
            content.text = footerText
            footer.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView, indexPath, row in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: row)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.open(row.id)
    }

    public func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let id = indexPaths.first.flatMap(dataSource.itemIdentifier(for:))?.id else {
            return nil
        }
        let style = style
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: style.openTitle, image: UIImage(systemName: style.openSymbol)) { _ in
                    self?.viewModel.open(id)
                },
                UIAction(title: style.takeBackTitle, image: UIImage(systemName: style.takeBackSymbol)) { _ in
                    self?.viewModel.takeBack(id)
                },
            ])
        })
    }
}

extension WaitingListStyle {
    static var scheduled: WaitingListStyle {
        WaitingListStyle(
            title: String(
                localized: "Scheduled", table: "Waiting", bundle: .module,
                comment: "Mailbox: messages waiting to be sent later"),
            emptySymbol: "clock",
            emptyText: String(
                localized: "Nothing Scheduled", table: "Waiting", bundle: .module,
                comment: "Shown when no message waits to be sent later"),
            emptyHint: String(
                localized: "Touch and hold Send to pick when a message goes.", table: "Waiting", bundle: .module,
                comment: "Explains how to schedule a message"),
            footer: String(
                localized:
                    "Goodmail sends these from this device. One may go a little late if the device is off or offline at the time.",
                table: "Waiting", bundle: .module, comment: "Explains that scheduled messages are sent by the device"),
            openTitle: String(
                localized: "Edit", table: "Waiting", bundle: .module, comment: "Opens a scheduled message to change it"),
            openSymbol: "pencil",
            takeBackTitle: String(
                localized: "Move to Drafts", table: "Waiting", bundle: .module,
                comment: "Keeps a scheduled message in Drafts instead"),
            takeBackSymbol: "doc",
            accessibilityIdentifier: "scheduled")
    }

    static var snoozed: WaitingListStyle {
        WaitingListStyle(
            title: String(
                localized: "Snoozed", table: "Waiting", bundle: .module, comment: "Mailbox: threads snoozed until later"
            ),
            emptySymbol: "moon.zzz",
            emptyText: String(
                localized: "Nothing Snoozed", table: "Waiting", bundle: .module,
                comment: "Shown when no thread is snoozed"),
            emptyHint: String(
                localized: "Snooze a thread to have it come back to the Inbox later.", table: "Waiting",
                bundle: .module,
                comment: "Explains what snoozing does"),
            footer: String(
                localized:
                    "Snoozed threads come back to the Inbox, unread, when Goodmail next checks for mail after their time.",
                table: "Waiting", bundle: .module, comment: "Explains when snoozed threads come back"),
            openTitle: String(
                localized: "Open", table: "Waiting", bundle: .module, comment: "Opens a snoozed thread to read it"),
            openSymbol: "envelope.open",
            takeBackTitle: String(
                localized: "Move to Inbox", table: "Waiting", bundle: .module,
                comment: "Puts a snoozed thread back in the Inbox now"),
            takeBackSymbol: "tray",
            accessibilityIdentifier: "snoozed")
    }
}

extension WaitingListViewController where Model == ScheduledViewModel {
    public static func scheduled(_ viewModel: ScheduledViewModel) -> WaitingListViewController {
        WaitingListViewController(viewModel: viewModel, style: .scheduled)
    }
}

extension WaitingListViewController where Model == SnoozedViewModel {
    public static func snoozed(_ viewModel: SnoozedViewModel) -> WaitingListViewController {
        WaitingListViewController(viewModel: viewModel, style: .snoozed)
    }
}
