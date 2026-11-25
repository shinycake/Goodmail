import MailCore
import UIKit

extension MailboxViewController {
    /// Only on a change: setting the configuration lays the view out again, which would run this again. Reads the
    /// rows on screen, not the model's, so nothing shows while rows are still going into a box or breaking up. Select
    /// goes with the last row and comes back with the first.
    func updateEmptyState() {
        // Only a bar showing this list morphs: under a pushed thread, laying the bar out would animate the reader's.
        let bar = navigationController.flatMap { $0.topViewController === self ? $0.navigationBar : nil }
        select.show(rows: dataSource.snapshot().numberOfItems, in: bar)
        let state = EmptyState.next(
            rowsShown: dataSource.snapshot().numberOfItems > 0, listing: viewModel.emptyListing, showing: emptyState,
            settled: filteredState() ?? inboxZeroState() ?? .empty(pointingTo: viewModel.categoryWithUnread),
            now: .now)
        guard state != emptyState else { return }
        recheckEmptyState(for: state)
        let previous = emptyState
        emptyState = state
        contentUnavailableConfiguration =
            switch state {
            case nil, .inboxZero: nil
            case .loading, .awaitingPage: UIContentUnavailableConfiguration.loading()
            case .empty(let other?): pointing(empty, to: other)
            case .empty(nil): empty
            case .filtered(let filter): filteredConfiguration(for: filter)
            }
        showInboxZero(for: state, after: previous)
    }

    /// While a cleared Inbox waits for its page, asks again once the wait is over, as nothing else may change by then.
    /// The one recheck is replaced, or cancelled, as the state moves on; one that comes anyway only asks again.
    private func recheckEmptyState(for state: EmptyState?) {
        emptyRecheck?.cancel()
        emptyRecheck = nil
        guard case .awaitingPage(let since) = state else { return }
        emptyRecheck = Task { [weak self] in
            try? await Task.sleep(until: since + EmptyState.pageWait, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.updateEmptyState()
        }
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

    static func noMail(in mailbox: Mailbox) -> UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: mailbox.symbol)
        configuration.text = String(
            localized: "No Mail", table: "Mailbox", bundle: .module, comment: "An empty mailbox")
        return configuration
    }
}
