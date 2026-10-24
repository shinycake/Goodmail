import MailCore
import UIKit

/// Shows a search's results in a mailbox list, and passes what is typed to the search.
public final class SearchResultsController: UIViewController, UISearchResultsUpdating {
    private let search: ThreadSearch
    private let list: MailboxViewController

    public init(search: ThreadSearch, accounts: [Account], navigate: @escaping (Route) -> Void, actions: MailActions?) {
        self.search = search
        list = MailboxViewController(
            viewModel: MailboxViewModel(
                mailbox: .allMail,
                title: String(localized: "Search", bundle: .module, comment: "Title of the search results list"),
                accounts: accounts,
                threads: { search.results() },
                refresh: { try await search.refresh() },
                navigate: navigate,
                actions: actions),
            empty: .search())
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addChild(list)
        list.view.frame = view.bounds
        list.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(list.view)
        list.didMove(toParent: self)
    }

    public func updateSearchResults(for searchController: UISearchController) {
        search.update(searchController.searchBar.text ?? "")
    }
}
