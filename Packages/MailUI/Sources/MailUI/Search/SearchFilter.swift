import MailCore
import UIKit

/// A search term shown as a token in the search field, such as Unread or From Dana.
nonisolated struct SearchFilter: Hashable {
    let term: SearchQuery.Term
    let title: String
    let symbol: String

    static let unread = SearchFilter(
        term: .unread,
        title: String(
            localized: "Search.Unread", defaultValue: "Unread", table: "Search", bundle: .module,
            comment: "Search filter for unread mail"),
        symbol: "envelope.badge")
    static let starred = SearchFilter(
        term: .starred,
        title: String(
            localized: "Search.Starred", defaultValue: "Starred", table: "Search", bundle: .module,
            comment: "Search filter for starred mail"),
        symbol: "star")
    static let hasAttachment = SearchFilter(
        term: .hasAttachment,
        title: String(
            localized: "Has Attachment", table: "Search", bundle: .module, comment: "Search filter for mail with files"),
        symbol: "paperclip")

    /// The filters offered before anything is typed.
    static let all = [unread, starred, hasAttachment]

    static func from(_ contact: Contact) -> SearchFilter {
        SearchFilter(term: .from(contact.address), title: contact.displayName, symbol: "person")
    }

    static func subject(_ text: String) -> SearchFilter {
        SearchFilter(term: .subject(text), title: text, symbol: "text.quote")
    }

    /// The filter a typed term stands for, so a recent search comes back with its tokens.
    init?(_ term: SearchQuery.Term) {
        if let known = Self.all.first(where: { $0.term == term }) {
            self = known
        } else if term.name == "from" {
            self = .from(Contact(name: nil, address: term.value))
        } else if term.name == "subject" {
            self = .subject(term.value)
        } else {
            return nil
        }
    }

    private init(term: SearchQuery.Term, title: String, symbol: String) {
        self.term = term
        self.title = title
        self.symbol = symbol
    }

    /// How the filter is offered while typing.
    var label: String {
        switch term.name {
        case "from":
            String(
                localized: "From \(title)", table: "Search", bundle: .module,
                comment: "Search suggestion: mail from a person")
        case "subject":
            String(
                localized: "Subject contains “\(title)”", table: "Search", bundle: .module,
                comment: "Search suggestion: mail whose subject has the typed text")
        default: title
        }
    }

    /// The address under a person's name.
    var detail: String? {
        term.name == "from" && term.value != title ? term.value : nil
    }

    @MainActor
    var token: UISearchToken {
        let token = UISearchToken(icon: UIImage(systemName: symbol), text: title)
        token.representedObject = term
        return token
    }
}
