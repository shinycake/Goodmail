import MailCore
import UIKit

/// Shows a search's results in a mailbox list, and passes what is typed to the search. While nothing is typed it
/// offers the recent searches instead.
public final class SearchResultsController: UIViewController, UISearchResultsUpdating, UISearchBarDelegate {
    private let search: ThreadSearch
    private let list: MailboxViewController
    private let recents: RecentSearches
    private let recentList = RecentSearchesViewController()
    private weak var searchController: UISearchController?

    public init(
        search: ThreadSearch, accounts: [Account], navigate: @escaping (Route) -> Void, actions: MailActions?,
        recents: RecentSearches = RecentSearches()
    ) {
        self.search = search
        self.recents = recents
        // Opening a result is what makes a search worth remembering.
        let navigate: (Route) -> Void = { route in
            if case .thread = route { recents.record(search.text) }
            navigate(route)
        }
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

        addChild(recentList)
        recentList.view.frame = view.bounds
        recentList.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(recentList.view)
        recentList.didMove(toParent: self)
        recentList.onSelect = { [weak self] text in
            guard let self, let searchController else { return }
            searchController.searchBar.text = text
            recents.record(text)
            updateSearchResults(for: searchController)
        }
        recentList.onClear = { [weak self] in
            guard let self, let searchController else { return }
            recents.clear()
            updateSearchResults(for: searchController)
        }
    }

    public func updateSearchResults(for searchController: UISearchController) {
        self.searchController = searchController
        searchController.searchBar.delegate = self
        let text = searchController.searchBar.text ?? ""
        search.update(text)
        let isBlank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let recentSearches = isBlank ? recents.all : []
        recentList.show(recentSearches)
        recentList.view.isHidden = !isBlank
        // With nothing typed and nothing recent, the mailbox stays in view behind the field.
        searchController.showsSearchResultsController = !isBlank || !recentSearches.isEmpty
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        recents.record(searchBar.text ?? "")
    }
}
