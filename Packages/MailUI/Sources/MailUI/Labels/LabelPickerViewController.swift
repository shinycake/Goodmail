import MailCore
import UIKit

/// A sheet listing the account's labels with a checkmark on each the threads carry. Done applies the changes.
public final class LabelPickerViewController: UIViewController {
    private var selection: LabelSelection
    private let apply: (ThreadAction) -> Void
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    /// `apply` runs on Done, only when something changed.
    public init(labels: [MailLabel], threads: [ThreadSummary], apply: @escaping (ThreadAction) -> Void) {
        selection = LabelSelection(labels: labels, threads: threads)
        self.apply = apply
        super.init(nibName: nil, bundle: nil)
        title = String(
            localized: "Labels", table: "Labels", bundle: .module, comment: "Section of user labels in the mailbox list"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                if let action = selection.action { apply(action) }
                dismiss(animated: true)
            })
        collectionView = UICollectionView(
            frame: view.bounds,
            collectionViewLayout: UICollectionViewCompositionalLayout.list(
                using: UICollectionLayoutListConfiguration(appearance: .insetGrouped)))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        view.addSubview(collectionView)

        let row = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let self, let choice = selection.choices.first(where: { $0.id == id }) else { return }
            var content = cell.defaultContentConfiguration()
            content.text = choice.label.name
            content.image = UIImage(systemName: "tag")
            content.imageProperties.tintColor = UIColor(labelColor: choice.label.color) ?? .tintColor
            cell.contentConfiguration = content
            switch choice.state {
            case .on: cell.accessories = [.checkmark()]
            case .mixed: cell.accessories = [.customView(configuration: Self.mixedMark())]
            case .off: cell.accessories = []
            }
            cell.accessibilityValue = Self.accessibilityValue(choice.state)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { view, indexPath, id in
            view.dequeueConfiguredReusableCell(using: row, for: indexPath, item: id)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(selection.choices.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// A dash where some of the threads carry the label.
    private static func mixedMark() -> UICellAccessory.CustomViewConfiguration {
        let dash = UIImageView(image: UIImage(systemName: "minus"))
        dash.tintColor = .tintColor
        return UICellAccessory.CustomViewConfiguration(customView: dash, placement: .trailing())
    }

    private static func accessibilityValue(_ state: LabelSelection.State) -> String {
        switch state {
        case .on:
            String(
                localized: "On", table: "Labels", bundle: .module, comment: "VoiceOver: the threads carry this label")
        case .off:
            String(
                localized: "Off", table: "Labels", bundle: .module, comment: "VoiceOver: the threads lack this label")
        case .mixed:
            String(
                localized: "Some", table: "Labels", bundle: .module,
                comment: "VoiceOver: some of the threads carry this label")
        }
    }
}

extension LabelPickerViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        selection.toggle(id)
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([id])
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}
