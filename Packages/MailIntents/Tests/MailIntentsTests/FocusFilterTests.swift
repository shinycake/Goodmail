import Foundation
import MailCore
import Testing

@testable import MailIntents

struct FocusFilterTests {
    private let work = Account(id: AccountID(rawValue: "work"), email: "me@work.example", color: .blue, service: .gmail)

    @Test func aFocusThatNamesNoAccountsShowsEveryAccount() {
        #expect(FocusFilter(showing: nil) == .everyAccount)
        #expect(FocusFilter(showing: []) == .everyAccount)
    }

    @Test func aFocusShowsTheAccountsItNames() {
        #expect(FocusFilter(showing: [AccountEntity(work)]) == .accounts([work.id]))
    }
}
