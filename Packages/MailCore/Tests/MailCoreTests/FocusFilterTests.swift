import Testing

@testable import MailCore

struct FocusFilterTests {
    private let work = AccountID(rawValue: "work")
    private let home = AccountID(rawValue: "home")

    @Test func withoutAFocusEveryAccountShows() {
        #expect(FocusFilter.everyAccount.includes(work))
    }

    @Test func aFocusShowsOnlyTheAccountsItNames() {
        let focus = FocusFilter.accounts([work])
        #expect(focus.includes(work))
        #expect(!focus.includes(home))
    }
}
