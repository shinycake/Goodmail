import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct SettingsTests {
    private let personal = Account(id: AccountID(rawValue: "a"), email: "me@example.com", color: .blue)
    private let work = Account(id: AccountID(rawValue: "b"), email: "work@example.com", color: .orange)

    @Test func addingAndRemovingReadTheAccountsBack() async {
        var stored = [personal]
        var closed = false
        let model = SettingsViewModel(
            accounts: { stored },
            add: {
                stored.append(work)
                return true
            },
            remove: { id in stored.removeAll { $0.id == id } },
            closed: { closed = true })
        #expect(model.accounts == [personal])
        await model.addAccount()
        #expect(model.accounts == [personal, work])
        #expect(!model.isAddingAccount)
        await model.removeAccount(personal.id)
        #expect(model.accounts == [work])
        model.didClose()
        #expect(closed)
    }

    @Test func aFailedSignInIsShownAndChangesNothing() async {
        struct Denied: Error {}
        let model = SettingsViewModel(
            accounts: { [personal] }, add: { throw Denied() }, remove: { _ in }, closed: {})
        await model.addAccount()
        #expect(model.error is Denied)
        #expect(model.accounts == [personal])
    }

    @Test func undoSendTitlesReadAsDurations() {
        #expect(SettingsViewModel.undoSendTitle(0) == "Off")
        #expect(SettingsViewModel.undoSendTitle(10) == "10 seconds")
    }
}
