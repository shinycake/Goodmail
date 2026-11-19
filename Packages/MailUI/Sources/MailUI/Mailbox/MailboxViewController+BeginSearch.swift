public import MailCore
import UIKit

extension MailboxViewController {
    /// Opens search with `query` in the field: ready to type in when it is empty, showing its results otherwise, as
    /// for a Home Screen quick action. A list not yet in a window begins it once it appears.
    public func beginSearch(_ query: SearchQuery) {
        guard viewIfLoaded?.window != nil else {
            searchToBegin = query
            return
        }
        searchToBegin = nil
        // Selecting takes search away.
        if isEditing { setEditing(false, animated: false) }
        guard let search, let searchResults else { return }
        searchResults.show(query, in: search.searchBar.searchTextField)
        search.isActive = true
        if query.isEmpty {
            search.searchBar.becomeFirstResponder()
        } else {
            searchResults.updateSearchResults(for: search)
        }
    }
}
