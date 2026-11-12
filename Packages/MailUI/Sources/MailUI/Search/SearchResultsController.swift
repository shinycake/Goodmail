import MailCore
import UIKit

/// Shows a search's results in a mailbox list, and passes what is typed to the search, with its filters as tokens.
/// Filters for what is typed are offered above the results; while nothing is typed, the recent searches too.
public final class SearchResultsController: UIViewController, UISearchResultsUpdating, UISearchBarDelegate {
    private let search: ThreadSearch
    private let list: MailboxViewController
    private let recents: RecentSearches
    private let contacts: (String) -> [Contact]
    private let suggestions = SearchSuggestionsViewController()
    private var suggestionsHeight: NSLayoutConstraint!
    private weak var searchController: UISearchController?

    public init(
        search: ThreadSearch, accounts: [Account], navigate: @escaping (Route) -> Void, actions: MailActions?,
        contacts: @escaping (String) -> [Contact] = { _ in [] }, recents: RecentSearches = RecentSearches()
    ) {
        self.search = search
        self.recents = recents
        self.contacts = contacts
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
        addChild(suggestions)
        addChild(list)
        let suggestionsView = suggestions.view!
        suggestionsView.translatesAutoresizingMaskIntoConstraints = false
        list.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(list.view)
        view.addSubview(suggestionsView)
        suggestionsHeight = suggestionsView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            suggestionsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            suggestionsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suggestionsHeight,
            list.view.topAnchor.constraint(equalTo: suggestionsView.bottomAnchor),
            list.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        suggestions.didMove(toParent: self)
        list.didMove(toParent: self)
        suggestions.onFilter = { [weak self] filter in
            guard let self, let searchController else { return }
            let field = searchController.searchBar.searchTextField
            // The typed text is what the filter was offered for, so the token takes its place.
            field.text = ""
            field.insertToken(filter.token, at: field.tokens.count)
            updateSearchResults(for: searchController)
        }
        suggestions.onSelect = { [weak self] text in
            guard let self, let searchController else { return }
            show(SearchQuery(text), in: searchController.searchBar.searchTextField)
            recents.record(text)
            updateSearchResults(for: searchController)
        }
        suggestions.onClear = { [weak self] in
            guard let self, let searchController else { return }
            recents.clear()
            updateSearchResults(for: searchController)
        }
    }

    public func updateSearchResults(for searchController: UISearchController) {
        self.searchController = searchController
        searchController.searchBar.delegate = self
        let field = searchController.searchBar.searchTextField
        let typed = field.text ?? ""
        let applied = field.tokens.compactMap { $0.representedObject as? SearchQuery.Term }
        let query = SearchQuery(terms: applied + SearchQuery(typed).terms)
        search.update(query.text)
        let recentSearches = query.isEmpty ? recents.all : []
        suggestions.show(filters: filters(for: typed, besides: applied), recents: recentSearches)
        // While nothing is asked, the suggestions stand alone; otherwise they sit above the results.
        list.view.isHidden = query.isEmpty
        suggestionsHeight.constant = min(suggestions.contentHeight, view.safeAreaLayoutGuide.layoutFrame.height)
        searchController.showsSearchResultsController = true
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        recents.record(search.text)
    }

    /// The filters to offer for what is typed: the filters it starts to spell, people it names, and its words in the
    /// subject. With nothing in the field at all, the plain filters; with only tokens, none, leaving the results.
    private func filters(for typed: String, besides applied: [SearchQuery.Term]) -> [SearchFilter] {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || applied.isEmpty else { return [] }
        let filters =
            text.isEmpty
            ? SearchFilter.all
            : SearchFilter.all.filter { $0.title.lowercased().hasPrefix(text.lowercased()) }
                + contacts(text).map(SearchFilter.from) + [.subject(text)]
        return filters.filter { !applied.contains($0.term) }
    }

    /// Puts a query in the field, its filters as tokens and the rest as text.
    private func show(_ query: SearchQuery, in field: UISearchTextField) {
        let filters = query.terms.compactMap(SearchFilter.init)
        field.tokens = filters.map(\.token)
        field.text = SearchQuery(terms: query.terms.filter { SearchFilter($0) == nil }).text
    }
}
