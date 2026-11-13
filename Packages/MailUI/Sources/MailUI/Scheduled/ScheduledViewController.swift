import MailCore
import UIKit

/// The messages waiting for their time. Tapping one opens it to edit; swiping keeps it in Drafts instead.
public final class ScheduledViewController: UIViewController {
    nonisolated private enum Section: Hashable {
        case messages
    }

    private let viewModel: ScheduledViewModel
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, ScheduledViewModel.Row>!
    private var observation: Task<Void, Never>?

    public init(viewModel: ScheduledViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = Self.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    deinit {
        observation?.cancel()
    }

    static var title: String {
        String(localized: "Scheduled", bundle: .module, comment: "Mailbox: messages waiting to be sent later")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.footerMode = .supplementary
        list.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, let row = dataSource.itemIdentifier(for: indexPath) else { return nil }
            return UISwipeActionsConfiguration(actions: [unscheduleAction(for: row)])
        }
        collectionView = UICollectionView(
            frame: view.bounds, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: list))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.accessibilityIdentifier = "scheduled"
        collectionView.delegate = self
        view.addSubview(collectionView)
        configureDataSource()
        observation = Task { [viewModel] in await viewModel.observe() }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    /// Called by UIKit whenever an observed view-model property changes.
    public override func updateProperties() {
        super.updateProperties()
        var snapshot = NSDiffableDataSourceSnapshot<Section, ScheduledViewModel.Row>()
        switch viewModel.content {
        case .loading:
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        case .loaded(let rows):
            contentUnavailableConfiguration = rows.isEmpty ? Self.nothingScheduled : nil
            if !rows.isEmpty {
                snapshot.appendSections([.messages])
                snapshot.appendItems(rows)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: collectionView.window != nil)
    }

    private static var nothingScheduled: UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "clock")
        configuration.text = String(
            localized: "Nothing Scheduled", bundle: .module, comment: "Shown when no message waits to be sent later")
        configuration.secondaryText = String(
            localized: "Touch and hold Send to pick when a message goes.", bundle: .module,
            comment: "Explains how to schedule a message")
        return configuration
    }

    private func unscheduleAction(for row: ScheduledViewModel.Row) -> UIContextualAction {
        let action = UIContextualAction(
            style: .normal,
            title: String(
                localized: "Move to Drafts", bundle: .module, comment: "Keeps a scheduled message in Drafts instead")
        ) { [weak self] _, _, done in
            self?.viewModel.unschedule(row.id)
            done(true)
        }
        action.image = UIImage(systemName: "doc")
        return action
    }

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, ScheduledViewModel.Row> {
            cell, _, row in
            var content = UIListContentConfiguration.subtitleCell()
            content.text = row.recipients
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryText = row.subject
            content.secondaryTextProperties.color = .secondaryLabel
            content.textToSecondaryTextVerticalPadding = 4
            cell.contentConfiguration = content
            var time = UICellAccessory.LabelOptions()
            time.font = .preferredFont(forTextStyle: .subheadline)
            time.tintColor = row.accountColor?.uiColor ?? .secondaryLabel
            cell.accessories = [.label(text: row.time, options: time)]
            cell.accessibilityIdentifier = "scheduled.\(row.id.uuidString)"
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { footer, _, _ in
            var content = UIListContentConfiguration.footer()
            content.text = String(
                localized:
                    "Goodmail sends these from this device. One may go a little late if the device is off or offline at the time.",
                bundle: .module, comment: "Explains that scheduled messages are sent by the device")
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
}

extension ScheduledViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.edit(row.id)
    }

    public func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let row = indexPaths.first.flatMap(dataSource.itemIdentifier(for:)) else {
            return nil
        }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: String(
                        localized: "Edit", bundle: .module, comment: "Opens a scheduled message to change it"),
                    image: UIImage(systemName: "pencil")
                ) { _ in self?.viewModel.edit(row.id) },
                UIAction(
                    title: String(
                        localized: "Move to Drafts", bundle: .module,
                        comment: "Keeps a scheduled message in Drafts instead"),
                    image: UIImage(systemName: "doc")
                ) { _ in self?.viewModel.unschedule(row.id) },
            ])
        })
    }
}
