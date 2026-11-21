import MailCore
import UIKit

/// The list's filter in the navigation bar, under the title, and in an empty list.
extension MailboxViewController {
    /// Shows the filter the list has: the button filled and the title area naming what is shown.
    func showFilter() {
        guard viewModel.offersFilter else { return }
        filterButton.show(viewModel.filter)
        navigationItem.subtitle = viewModel.filter.summary
    }

    /// Applies `filter`, from the top of the list, as a category does.
    func setFilter(_ filter: ListFilter) {
        viewModel.setFilter(filter)
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
    }

    /// The empty state of a filter that hides every conversation the mailbox has, or `nil` when it hides none.
    func filteredState() -> EmptyState? {
        viewModel.filter.isOn && viewModel.hiddenByFilter > 0 ? .filtered(viewModel.filter) : nil
    }

    /// What the list says while `filter` hides everything, with the way to turn it off.
    func filteredConfiguration(for filter: ListFilter) -> UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "line.3.horizontal.decrease.circle")
        configuration.text = filter.emptyTitle
        configuration.secondaryText = String(
            localized: "The filter leaves out everything in this mailbox.", table: "Mailbox", bundle: .module,
            comment: "An empty list while a filter hides every conversation")
        var button = UIButton.Configuration.plain()
        button.title = FilterButton.turnOffTitle
        configuration.button = button
        configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
            guard let self else { return }
            setFilter(viewModel.filter.toggled())
        }
        return configuration
    }
}
