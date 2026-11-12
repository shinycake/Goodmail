import MailCore
import Testing

@testable import MailUI

@MainActor
struct SearchFilterTests {
    @Test func aRecentSearchComesBackWithItsTokens() {
        let terms = SearchQuery("from:dana@example.com is:unread lunch in:sent subject:\"team plans\"").terms
        #expect(terms.compactMap(SearchFilter.init).map(\.title) == ["dana@example.com", "Unread", "team plans"])
        #expect(SearchFilter(.word("lunch")) == nil)
        #expect(SearchFilter(.init("in", "sent")) == nil, "operators without a token stay as text")
    }

    @Test func aPersonIsOfferedByNameWithTheAddressBeneath() {
        let filter = SearchFilter.from(Contact(name: "Dana Levi", address: "dana@example.com"))
        #expect(filter.label == "From Dana Levi")
        #expect(filter.detail == "dana@example.com")
        #expect(filter.token.representedObject as? SearchQuery.Term == .from("dana@example.com"))
        #expect(SearchFilter.from(Contact(name: nil, address: "a@b.c")).detail == nil)
    }
}
