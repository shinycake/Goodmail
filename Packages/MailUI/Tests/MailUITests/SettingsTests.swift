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
            signIn: { service in
                #expect(service == .gmail)
                stored.append(work)
                return true
            },
            remove: { id in stored.removeAll { $0.id == id } },
            update: { _ in },
            closed: { closed = true })
        #expect(model.accounts == [personal])
        await model.adder.add(.gmail)
        #expect(model.accounts == [personal, work])
        #expect(model.adder.state == .choosing)
        await model.removeAccount(personal.id)
        #expect(model.accounts == [work])
        model.didClose()
        await model.settled()
        #expect(closed)
    }

    @Test func quickChangesAreAllStoredInOrderBeforeTheScreenCloses() async {
        var stored = [personal]
        var events: [String] = []
        let model = SettingsViewModel(
            accounts: { stored }, signIn: { _ in true }, remove: { _ in },
            update: { account in
                // A slow write, so the next change is made before this one is stored.
                try await Task.sleep(for: .milliseconds(20))
                stored = [account]
                events.append("stored \(account.name ?? "-") \(account.color)")
            },
            closed: { events.append("closed") })

        model.rename(personal.id, to: "  Me  ")
        model.setColor(.green, for: personal.id)
        #expect(model.accounts.first?.name == "Me", "shown at once")
        #expect(model.accounts.first?.color == .green)
        model.didClose()
        await model.settled()

        #expect(events == ["stored Me blue", "stored Me green", "closed"])
        #expect(stored.first?.name == "Me", "the color change didn't overwrite the rename")
        #expect(stored.first?.color == .green)
    }

    @Test func aFailedRenameIsNotStoredByTheColorChangeAfterIt() async {
        struct Refused: Error {}
        var stored = [personal]
        let model = SettingsViewModel(
            accounts: { stored }, signIn: { _ in true }, remove: { _ in },
            update: { account in
                try await Task.sleep(for: .milliseconds(20))
                if account.name != personal.name { throw Refused() }
                stored = [account]
            },
            closed: {})

        model.rename(personal.id, to: "Me")
        model.setColor(.green, for: personal.id)
        #expect(model.accounts.first?.name == "Me", "both shown while they wait")
        #expect(model.accounts.first?.color == .green)
        await model.settled()

        #expect(model.error is Refused)
        #expect(stored.first?.name == personal.name, "the failed rename stays unstored")
        #expect(stored.first?.color == .green)
        #expect(model.accounts == stored, "the screen shows what is stored")
    }

    @Test func aFailedChangeIsShownAndTheAccountReadsBackAsStored() async {
        struct Refused: Error {}
        let model = SettingsViewModel(
            accounts: { [personal] }, signIn: { _ in true }, remove: { _ in }, update: { _ in throw Refused() },
            closed: {})
        model.setColor(.green, for: personal.id)
        await model.settled()
        #expect(model.error is Refused)
        #expect(model.accounts == [personal])
    }

    @Test func aFailedSignInIsShownAndChangesNothing() async {
        struct Denied: Error {}
        let model = SettingsViewModel(
            accounts: { [personal] }, signIn: { _ in throw Denied() }, remove: { _ in }, update: { _ in },
            closed: {})
        await model.adder.add(.gmail)
        #expect(model.adder.error is Denied)
        #expect(model.accounts == [personal])
    }

    @Test func inboxCategoriesTurnOffPerAccountAndPersist() {
        let saved = Preferences.unsortedInboxAccounts
        defer { Preferences.unsortedInboxAccounts = saved }
        Preferences.unsortedInboxAccounts = []
        let model = SettingsViewModel(
            accounts: { [personal, work] }, signIn: { _ in true }, remove: { _ in }, update: { _ in }, closed: {})
        #expect(model.sortsInbox(work.id), "categories are on by default")

        model.setSortsInbox(false, for: work.id)
        #expect(!model.sortsInbox(work.id))
        #expect(model.sortsInbox(personal.id))
        #expect(Preferences.unsortedInboxAccounts == [work.id])

        model.setSortsInbox(true, for: work.id)
        #expect(Preferences.unsortedInboxAccounts.isEmpty)
    }

    @Test func theMailListsLookPersists() {
        let saved = Preferences.rowDisplay
        defer { Preferences.rowDisplay = saved }
        Preferences.rowDisplay = .standard
        let model = SettingsViewModel(
            accounts: { [personal] }, signIn: { _ in true }, remove: { _ in }, update: { _ in }, closed: {})
        #expect(model.rowDisplay == RowDisplay(previewLines: 2, showsAvatars: true), "two lines and avatars at first")

        model.rowDisplay.previewLines = 0
        model.rowDisplay.showsAvatars = false
        #expect(Preferences.rowDisplay == RowDisplay(previewLines: 0, showsAvatars: false))

        Preferences.rowDisplay.previewLines = 7
        #expect(Preferences.rowDisplay.previewLines == 2, "a length the picker doesn't offer reads as the standard")
    }

    @Test func previewTitlesReadAsLines() {
        #expect(RowDisplay.previewTitle(0) == "None")
        #expect(RowDisplay.previewTitle(1) == "1 line")
        #expect(RowDisplay.previewTitle(3) == "3 lines")
    }

    @Test func renamingTrimsTheNameAndABlankOneClearsIt() async {
        var stored = [personal, work]
        var updates = 0
        let model = SettingsViewModel(
            accounts: { stored }, signIn: { _ in true }, remove: { _ in },
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
        await model.settled()
        #expect(updates == 2)
    }

    @Test func recoloringStoresOnlyARealChange() async {
        var stored = [personal]
        var updates = 0
        let model = SettingsViewModel(
            accounts: { stored }, signIn: { _ in true }, remove: { _ in },
            update: { account in
                updates += 1
                stored = [account]
            },
            closed: {})

        model.setColor(.blue, for: personal.id)
        await model.settled()
        #expect(updates == 0, "the color it already has")
        model.setColor(.mint, for: personal.id)
        #expect(model.accounts[0].color == .mint)
        await model.settled()
        #expect(updates == 1)
    }

    @Test func aFailedUpdateIsShownAndChangesNothing() async {
        struct Locked: Error {}
        let model = SettingsViewModel(
            accounts: { [personal] }, signIn: { _ in true }, remove: { _ in }, update: { _ in throw Locked() },
            closed: {})
        model.setColor(.mint, for: personal.id)
        await model.settled()
        #expect(model.error is Locked)
        #expect(model.accounts == [personal])
    }

    @Test func undoSendTitlesReadAsDurations() {
        #expect(SettingsViewModel.undoSendTitle(0) == "Off")
        #expect(SettingsViewModel.undoSendTitle(10) == "10 seconds")
    }
}
