import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct SettingsTests {
    private let personal = Account(id: AccountID(rawValue: "a"), email: "me@example.com", color: .blue, service: .gmail)
    private let work = Account(id: AccountID(rawValue: "b"), email: "work@example.com", color: .orange, service: .gmail)

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
            update: { _ in },
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
            accounts: { [personal] }, add: { throw Denied() }, remove: { _ in }, update: { _ in }, closed: {})
        await model.addAccount()
        #expect(model.error is Denied)
        #expect(model.accounts == [personal])
    }

    @Test func inboxCategoriesTurnOffPerAccountAndPersist() {
        let saved = Preferences.unsortedInboxAccounts
        defer { Preferences.unsortedInboxAccounts = saved }
        Preferences.unsortedInboxAccounts = []
        let model = SettingsViewModel(
            accounts: { [personal, work] }, add: { true }, remove: { _ in }, update: { _ in }, closed: {})
        #expect(model.sortsInbox(work.id), "categories are on by default")

        model.setSortsInbox(false, for: work.id)
        #expect(!model.sortsInbox(work.id))
        #expect(model.sortsInbox(personal.id))
        #expect(Preferences.unsortedInboxAccounts == [work.id])

        model.setSortsInbox(true, for: work.id)
        #expect(Preferences.unsortedInboxAccounts.isEmpty)
    }

    @Test func renamingTrimsTheNameAndABlankOneClearsIt() {
        var stored = [personal, work]
        var updates = 0
        let model = SettingsViewModel(
            accounts: { stored }, add: { true }, remove: { _ in },
            update: { account in
                updates += 1
                stored = stored.map { $0.id == account.id ? account : $0 }
            },
            closed: {})

        model.rename(work.id, to: "  Dana Levi \n")
        #expect(model.accounts[1].name == "Dana Levi")
        #expect(model.accounts[0].name == nil, "other accounts keep theirs")

        model.rename(work.id, to: "   ")
        #expect(model.accounts[1].name == nil)
        #expect(updates == 2)
    }

    @Test func recoloringStoresOnlyARealChange() {
        var stored = [personal]
        var updates = 0
        let model = SettingsViewModel(
            accounts: { stored }, add: { true }, remove: { _ in },
            update: { account in
                updates += 1
                stored = [account]
            },
            closed: {})

        model.setColor(.blue, for: personal.id)
        #expect(updates == 0, "the color it already has")
        model.setColor(.mint, for: personal.id)
        #expect(model.accounts[0].color == .mint)
        #expect(updates == 1)
    }

    @Test func aFailedUpdateIsShownAndChangesNothing() {
        struct Locked: Error {}
        let model = SettingsViewModel(
            accounts: { [personal] }, add: { true }, remove: { _ in }, update: { _ in throw Locked() }, closed: {})
        model.setColor(.mint, for: personal.id)
        #expect(model.error is Locked)
        #expect(model.accounts == [personal])
    }

    @Test func undoSendTitlesReadAsDurations() {
        #expect(SettingsViewModel.undoSendTitle(0) == "Off")
        #expect(SettingsViewModel.undoSendTitle(10) == "10 seconds")
    }
}
