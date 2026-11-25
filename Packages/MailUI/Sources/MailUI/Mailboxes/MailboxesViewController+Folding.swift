import MailCore
public import UIKit

/// A row of the mailboxes list: a mailbox, or in a sidebar the header row a section folds under.
nonisolated enum SidebarRow: Hashable, Sendable {
    case header(MailboxesViewModel.Section)
    case mailbox(MailboxesViewModel.Item)

    var item: MailboxesViewModel.Item? {
        guard case .mailbox(let item) = self else { return nil }
        return item
    }
}

/// Folding the sidebar's sections: each section with a header folds under it, by its chevron, a click on it, or the
/// left and right arrows while it has the keyboard, stays as the reader left it on this device, and counts the unread
/// threads it hides. The list on iPhone keeps plain headers.
extension MailboxesViewController {
    func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self else { return nil }
            var list = UICollectionLayoutListConfiguration(appearance: style == .sidebar ? .sidebar : .insetGrouped)
            let section = dataSource?.sectionIdentifier(for: index)
            list.headerMode =
                switch (style, section) {
                case (.list, _): .supplementary
                case (.sidebar, .some(let section)) where viewModel.foldsUnderHeader(section): .firstItemInSection
                case (.sidebar, _): .none
                }
            // The list's sections would paint over the doodles behind it, which paint the grouped background
            // themselves.
            if style == .list { list.backgroundColor = .clear }
            list.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.swipeActions(at: indexPath)
            }
            return NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
        }
    }

    /// What a section's header says: nothing over the standard mailboxes, Labels over the only account's labels, and
    /// an account's address with its service's logo.
    static func headerContent(for section: MailboxesViewModel.Section) -> UIListContentConfiguration {
        // A sidebar list's header takes the sidebar's look by itself (iOS 18).
        var content = UIListContentConfiguration.header()
        switch section {
        case .mailboxes: break
        case .smartMailboxes: content.text = SmartMailbox.sectionTitle
        case .labels:
            content.text = String(
                localized: "Labels", table: "Mailboxes", bundle: .module, comment: "Header above the user's labels")
        case .account(let account):
            // The service's logo beside the account's name; its color is on its mailboxes' icons below.
            content.text = account.title
            // An address wraps, rather than clips, in a sidebar at the largest text sizes.
            content.textProperties.numberOfLines = 0
            content.image = account.service.markImage
            // The same box for a logo and a symbol, so every account's address starts at one edge.
            content.imageProperties.maximumSize = CGSize(width: 18, height: 18)
            content.imageProperties.reservedLayoutSize = CGSize(width: 18, height: 18)
        }
        return content
    }

    /// A section's header row: its title, the chevron that folds it, and while it is folded, the unread threads in
    /// it.
    func foldingHeaderRegistration()
        -> UICollectionView.CellRegistration<UICollectionViewListCell, MailboxesViewModel.Section>
    {
        UICollectionView.CellRegistration { [weak self] cell, _, section in
            let content = Self.headerContent(for: section)
            let unread = self?.sectionUnread[section] ?? 0
            cell.configurationUpdateHandler = { cell, state in
                guard let cell = cell as? UICollectionViewListCell else { return }
                cell.contentConfiguration = content
                let count: [UICellAccessory] =
                    !state.isExpanded && unread > 0 ? [.label(text: unread.formatted())] : []
                cell.accessories = count + [.outlineDisclosure(options: .init(style: .header))]
            }
            cell.accessibilityTraits.insert(.header)
            cell.accessibilityIdentifier = "section.\(section.foldingKey)"
        }
    }

    /// Keeps a header's unread count current, redrawing only the headers whose count changed.
    func updateFoldedCounts(_ groups: [MailboxesViewModel.Group]) {
        let counts = Dictionary(uniqueKeysWithValues: groups.map { ($0.section, $0.unread) })
        let changed = counts.filter { sectionUnread[$0.key] != $0.value }.map(\.key).filter(viewModel.foldsUnderHeader)
        sectionUnread = counts
        var snapshot = dataSource.snapshot()
        let headers = changed.map(SidebarRow.header).filter { snapshot.indexOfItem($0) != nil }
        guard !headers.isEmpty else { return }
        snapshot.reconfigureItems(headers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Left folds and right unfolds the section whose header has the keyboard, the way they work a Finder sidebar,
    /// mirrored for right-to-left.
    public override var keyCommands: [UIKeyCommand]? {
        guard style == .sidebar else { return super.keyCommands }
        let arrows = [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow].map {
            UIKeyCommand(input: $0, modifierFlags: [], action: #selector(foldFocusedSection(_:)))
        }
        return (super.keyCommands ?? []) + arrows
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard action == #selector(foldFocusedSection(_:)) else {
            return super.canPerformAction(action, withSender: sender)
        }
        return focusedHeader != nil
    }

    @objc private func foldFocusedSection(_ command: UIKeyCommand) {
        guard let focusedHeader else { return }
        let rightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let unfolds = (command.input == UIKeyCommand.inputRightArrow) != rightToLeft
        viewModel.fold(focusedHeader, folded: !unfolds)
    }

    /// The header row that has the keyboard, if one does.
    private var focusedHeader: SidebarRow? {
        guard let cell = UIFocusSystem.focusSystem(for: view)?.focusedItem as? UICollectionViewCell,
            let indexPath = collectionView.indexPath(for: cell),
            let row = dataSource.itemIdentifier(for: indexPath), case .header = row
        else { return nil }
        return row
    }
}
